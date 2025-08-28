Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Authenticated routes
  authenticate :user do
    resources :data_source_connections do
      member do
        post :test_connection
        post :sync_schema
        get :list_tables
      end
    end
    
    resources :datasets do
      member do
        post :analyze
      end
    end
    
    resources :analysis_requests, only: [:index, :show, :destroy] do
      member do
        get :export
      end
    end
    
    resources :scheduled_reports do
      member do
        patch :enable
        patch :disable
        post :run_now
      end
    end
    
    get "dashboard", to: "dashboard#index"
  end

  # Defines the root path route ("/")
  root "pages#home"
end
