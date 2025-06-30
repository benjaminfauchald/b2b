# frozen_string_literal: true

module PhantomBusterHelpers
  # Standard PhantomBuster API stubs for testing

  def stub_phantombuster_config_fetch(phantom_id: 'test_phantom_id', api_key: 'test_api_key', current_config: {})
    stub_request(:get, "https://api.phantombuster.com/api/v2/agents/fetch?id=#{phantom_id}")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(
        status: 200,
        body: {
          argument: current_config.to_json
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_config_save(phantom_id: 'test_phantom_id', api_key: 'test_api_key')
    stub_request(:post, "https://api.phantombuster.com/api/v2/agents/save")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key,
          'Content-Type' => 'application/json'
        }
      )
      .to_return(status: 200, body: '{}')
  end

  def stub_phantombuster_launch(phantom_id: 'test_phantom_id', api_key: 'test_api_key', container_id: 'test_container_123')
    stub_request(:post, "https://api.phantombuster.com/api/v2/agents/launch")
      .with(
        body: { id: phantom_id }.to_json,
        headers: {
          'X-Phantombuster-Key-1' => api_key,
          'Content-Type' => 'application/json'
        }
      )
      .to_return(
        status: 200,
        body: { containerId: container_id }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_monitor_success(container_id: 'test_container_123', api_key: 'test_api_key', json_url: 'https://example.com/results.json')
    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch?id=#{container_id}")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(
        status: 200,
        body: { status: 'success' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch-output?id=#{container_id}")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(
        status: 200,
        body: {
          output: "JSON saved at #{json_url}"
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_monitor_failure(container_id: 'test_container_123', api_key: 'test_api_key', status: 'failed')
    stub_request(:get, "https://api.phantombuster.com/api/v2/containers/fetch?id=#{container_id}")
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(
        status: 200,
        body: { status: status }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_results(json_url: 'https://example.com/results.json', profiles: default_phantom_profiles)
    stub_request(:get, json_url)
      .to_return(
        status: 200,
        body: profiles.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_phantombuster_api_error(endpoint: 'agents/fetch', phantom_id: 'test_phantom_id', api_key: 'test_api_key', status: 500)
    url = case endpoint
    when 'agents/fetch'
            "https://api.phantombuster.com/api/v2/agents/fetch?id=#{phantom_id}"
    when 'agents/save'
            "https://api.phantombuster.com/api/v2/agents/save"
    when 'agents/launch'
            "https://api.phantombuster.com/api/v2/agents/launch"
    else
            raise "Unknown endpoint: #{endpoint}"
    end

    stub_request(:any, url)
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(status: status, body: 'Internal Server Error')
  end

  def stub_phantombuster_rate_limit(endpoint: 'agents/launch', phantom_id: 'test_phantom_id', api_key: 'test_api_key', retry_after: 60)
    url = case endpoint
    when 'agents/fetch'
            "https://api.phantombuster.com/api/v2/agents/fetch?id=#{phantom_id}"
    when 'agents/save'
            "https://api.phantombuster.com/api/v2/agents/save"
    when 'agents/launch'
            "https://api.phantombuster.com/api/v2/agents/launch"
    else
            raise "Unknown endpoint: #{endpoint}"
    end

    stub_request(:any, url)
      .with(
        headers: {
          'X-Phantombuster-Key-1' => api_key
        }
      )
      .to_return(
        status: 429,
        body: { error: 'Rate limit exceeded', retry_after: retry_after }.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'Retry-After' => retry_after.to_s
        }
      )
  end

  private

  def default_phantom_profiles
    [
      {
        'fullName' => 'John Doe',
        'title' => 'Software Engineer',
        'location' => 'San Francisco',
        'linkedInProfileUrl' => 'https://linkedin.com/in/johndoe',
        'email' => 'john@example.com',
        'connectionDegree' => '2nd'
      },
      {
        'fullName' => 'Jane Smith',
        'title' => 'Product Manager',
        'location' => 'New York',
        'linkedInProfileUrl' => 'https://linkedin.com/in/janesmith',
        'email' => 'jane@example.com',
        'connectionDegree' => '1st'
      },
      {
        'fullName' => 'Bob Wilson',
        'title' => 'Designer',
        'location' => 'Austin',
        'linkedInProfileUrl' => 'https://linkedin.com/in/bobwilson',
        'email' => 'bob@example.com',
        'connectionDegree' => '3rd'
      }
    ]
  end
end

RSpec.configure do |config|
  config.include PhantomBusterHelpers
end
