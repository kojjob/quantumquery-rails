Rails.application.routes.draw do
  devise_for :users
  
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  
  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end
  
  root "pages#home"
  
  get 'dashboard', to: 'dashboard#index', as: :dashboard
  
  resources :analysis_requests do
    member do
      get :status
      get :export
      get :share
    end
  end
  
  resources :datasets do
    member do
      post :test_connection
      post :fetch_schema
      get :sample_data
    end
  end
  
  resources :execution_steps, only: [:show] do
    member do
      get :output
      get :download_artifact
    end
  end
  
  namespace :api do
    namespace :v1 do
      resources :analysis_requests, only: [:create, :show, :index] do
        member do
          get :status
        end
      end
    end
  end
end
