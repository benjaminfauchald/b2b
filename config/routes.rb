require "sidekiq/web"

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  }
  resources :domains do
    collection do
      post :queue_testing
      post :queue_dns_testing
      post :queue_mx_testing
      post :queue_a_record_testing
      get :queue_status
      get :import, to: "domains#import_csv"
      post :import, to: "domains#process_import"
      get :import_results, to: "domains#import_results"
      get :template, to: "domains#download_template"
      get :export_errors, to: "domains#export_errors"
    end

    member do
      post :queue_single_dns
      post :queue_single_mx
      post :queue_single_www
    end
  end

  resources :companies do
    collection do
      # Enhancement service queue actions
      post :queue_financial_data
      post :queue_web_discovery
      post :queue_linkedin_discovery
      post :queue_employee_discovery
      get :enhancement_queue_status
      get :service_stats
    end

    member do
      # Individual company service triggers
      post :queue_single_financial_data
      post :queue_single_web_discovery
      post :queue_single_linkedin_discovery
      post :queue_single_employee_discovery
      get :financial_data
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Version endpoint for deployment verification
  get "version" => "application#version", as: :version_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Welcome page
  get "welcome", to: "welcome#index"

  # Test routes (development only)
  if Rails.env.development?
    get "test/web_discovery", to: "test#web_discovery_test"
    post "test/run_web_discovery", to: "test#run_web_discovery"
    get "test/linkedin_discovery", to: "test#linkedin_discovery_test"
    post "test/run_linkedin_discovery", to: "test#run_linkedin_discovery"
  end

  # Defines the root path route ("/")
  root "welcome#index"

  namespace :webhooks do
    post "/instantly", to: "instantly_webhook#create"
  end

  # ------------------------------------------------------------------
  # Quality Dashboard
  # ------------------------------------------------------------------
  # HTML + JSON endpoints for service quality insights.
  # - index  : /quality            => QualityDashboard#index
  # - show   : /quality/:id        => QualityDashboard#show
  # - member : /quality/:id/hourly_stats (AJAX JSON)
  # - member : /quality/:id/daily_stats  (AJAX JSON)
  # - POST   : /quality/refresh    => QualityDashboard#refresh_stats (admin only)
  resources :quality_dashboard, only: %i[index show], path: "quality" do
    member do
      get :hourly_stats, to: "quality_dashboard#service_hourly_stats"
      get :daily_stats,  to: "quality_dashboard#service_daily_stats"
    end

    collection do
      post :refresh, to: "quality_dashboard#refresh_stats"
    end
  end

  # Sidekiq Web UI with environment-specific authentication
  require "sidekiq/web"

  # Temporarily allow access without authentication for debugging
  mount Sidekiq::Web => "/sidekiq"

  # if Rails.env.development?
  #   # In development, allow access without authentication for easier debugging
  #   mount Sidekiq::Web => '/sidekiq'
  # else
  #   # In production, require admin authentication
  #   authenticate :user, lambda { |u| u.admin? } do
  #     mount Sidekiq::Web => '/sidekiq'
  #   end
  # end
end
