# spec/support/latest_service_run_stub.rb
class LatestServiceRun
  def self.find_by(*args)
    nil
  end
end
