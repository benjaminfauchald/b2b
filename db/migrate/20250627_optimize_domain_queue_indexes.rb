class OptimizeDomainQueueIndexes < ActiveRecord::Migration[8.0]
  def change
    # Add indexes for domain testing status columns
    add_index :domains, :dns, name: 'index_domains_on_dns'
    add_index :domains, :mx, name: 'index_domains_on_mx'
    add_index :domains, :www, name: 'index_domains_on_www'
    
    # Add composite indexes for common query patterns
    add_index :domains, [:dns, :mx], name: 'index_domains_on_dns_and_mx'
    add_index :domains, [:dns, :www], name: 'index_domains_on_dns_and_www'
    add_index :domains, [:www, :a_record_ip], name: 'index_domains_on_www_and_a_record_ip'
    
    # Add partial indexes for specific queue queries
    add_index :domains, :id, where: "dns IS NULL", name: 'index_domains_needing_dns'
    add_index :domains, :id, where: "dns = true AND mx IS NULL", name: 'index_domains_needing_mx'
    add_index :domains, :id, where: "dns = true AND www IS NULL", name: 'index_domains_needing_www'
    add_index :domains, :id, where: "www = true AND a_record_ip IS NOT NULL AND web_content_data IS NULL", 
              name: 'index_domains_needing_web_content'
    
    # Add index for completed_at on service_audit_logs for faster time-based queries
    add_index :service_audit_logs, :completed_at, name: 'index_service_audit_logs_on_completed_at'
    
    # Add composite index for the needing_service subquery pattern
    add_index :service_audit_logs, [:auditable_type, :service_name, :status, :completed_at], 
              name: 'index_sal_type_service_status_completed'
  end
end