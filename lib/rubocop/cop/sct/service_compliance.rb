# frozen_string_literal: true

module RuboCop
  module Cop
    module SCT
      # Cop to enforce SCT pattern compliance in ApplicationService subclasses
      #
      # @example
      #   # bad
      #   class MyService < ApplicationService
      #     def call
      #       # implementation
      #     end
      #   end
      #
      #   # good
      #   class MyService < ApplicationService
      #     def initialize(**options)
      #       super(service_name: "my_service", action: "process", **options)
      #     end
      #
      #     def perform
      #       # implementation using audit_service_operation
      #     end
      #
      #     private
      #
      #     def service_active?
      #       # implementation
      #     end
      #
      #     def success_result(message, data = {})
      #       # implementation
      #     end
      #
      #     def error_result(message, data = {})
      #       # implementation
      #     end
      #   end
      class ServiceCompliance < Base
        MSG_MISSING_PERFORM = 'ApplicationService subclasses must implement #perform method'
        MSG_MISSING_SERVICE_ACTIVE = 'ApplicationService subclasses must implement #service_active? method'
        MSG_MISSING_SUCCESS_RESULT = 'ApplicationService subclasses must implement #success_result method'
        MSG_MISSING_ERROR_RESULT = 'ApplicationService subclasses must implement #error_result method'
        MSG_MISSING_SUPER_CALL = 'ApplicationService subclasses must call super() in initialize with service_name and action'
        MSG_SHOULD_USE_AUDIT_OPERATION = 'Consider using audit_service_operation for proper audit tracking'
        MSG_AVOID_MANUAL_AUDIT_LOG = 'Avoid manual ServiceAuditLog.create! - use audit_service_operation instead'
        MSG_MISSING_SERVICE_CONFIG_CHECK = 'Service should check service_active? before performing operations'

        def_node_matcher :application_service_subclass?, <<~PATTERN
          (class
            (const nil? _)
            (const nil? :ApplicationService)
            ...
          )
        PATTERN

        def_node_matcher :method_def?, <<~PATTERN
          (def $_ ...)
        PATTERN

        def_node_matcher :super_call_with_service_name?, <<~PATTERN
          (super
            (hash
              (pair (sym :service_name) _)
              ...
            )
          )
        PATTERN

        def_node_matcher :manual_audit_log_creation?, <<~PATTERN
          (send (const nil? :ServiceAuditLog) :create! ...)
        PATTERN

        def_node_matcher :audit_service_operation_usage?, <<~PATTERN
          (send nil? :audit_service_operation ...)
        PATTERN

        def_node_matcher :service_active_check?, <<~PATTERN
          (send nil? :service_active?)
        PATTERN

        def on_class(node)
          return unless application_service_subclass?(node)

          class_name = node.children[0].children[1]
          return if excluded_service?(class_name)

          check_required_methods(node)
          check_initialize_method(node)
          check_audit_patterns(node)
          check_service_active_usage(node)
        end

        private

        def excluded_service?(class_name)
          # Exclude base classes and test utilities
          %w[ApplicationService TestService].include?(class_name.to_s)
        end

        def check_required_methods(node)
          methods = extract_method_names(node)
          
          add_offense(node, message: MSG_MISSING_PERFORM) unless methods.include?(:perform)
          add_offense(node, message: MSG_MISSING_SERVICE_ACTIVE) unless methods.include?(:service_active?)
          add_offense(node, message: MSG_MISSING_SUCCESS_RESULT) unless methods.include?(:success_result)
          add_offense(node, message: MSG_MISSING_ERROR_RESULT) unless methods.include?(:error_result)
        end

        def check_initialize_method(node)
          initialize_method = find_method(node, :initialize)
          return unless initialize_method

          has_super_call = initialize_method.each_descendant(:super).any? do |super_node|
            super_call_with_service_name?(super_node)
          end

          add_offense(initialize_method, message: MSG_MISSING_SUPER_CALL) unless has_super_call
        end

        def check_audit_patterns(node)
          has_audit_operation = node.each_descendant.any? { |n| audit_service_operation_usage?(n) }
          has_manual_audit = node.each_descendant.any? { |n| manual_audit_log_creation?(n) }

          if has_manual_audit && !has_audit_operation
            manual_audit_nodes = node.each_descendant.select { |n| manual_audit_log_creation?(n) }
            manual_audit_nodes.each do |audit_node|
              add_offense(audit_node, message: MSG_AVOID_MANUAL_AUDIT_LOG)
            end
          end

          unless has_audit_operation
            add_offense(node, message: MSG_SHOULD_USE_AUDIT_OPERATION)
          end
        end

        def check_service_active_usage(node)
          perform_method = find_method(node, :perform)
          return unless perform_method

          has_service_active_check = perform_method.each_descendant.any? do |n|
            service_active_check?(n)
          end

          unless has_service_active_check
            add_offense(perform_method, message: MSG_MISSING_SERVICE_CONFIG_CHECK)
          end
        end

        def extract_method_names(node)
          node.each_descendant(:def).map do |method_node|
            method_def?(method_node)
          end.compact
        end

        def find_method(node, method_name)
          node.each_descendant(:def).find do |method_node|
            method_def?(method_node) == method_name
          end
        end
      end
    end
  end
end