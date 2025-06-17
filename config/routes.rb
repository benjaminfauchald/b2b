Rails.application.routes.draw do
  devise_for :users
  resources :domains
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "domains#index"

  namespace :webhooks do
    post '/instantly', to: 'instantly_webhook#create'
  end

  # Sidekiq Web UI with environment-specific authentication
  require 'sidekiq/web'
  
  # Temporarily allow access without authentication for debugging
  mount Sidekiq::Web => '/sidekiq'
  
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
