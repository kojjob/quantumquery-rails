Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # API Token Management
  resources :api_tokens do
    member do
      post :revoke
    end
  end

  # API Routes
  namespace :api do
    namespace :v1 do
      # API Documentation
      get "documentation", to: "documentation#index"
      
      # Dataset endpoints
      resources :datasets
      
      # Analysis endpoints
      resources :analysis, only: [:index, :show, :create] do
        member do
          post :cancel
        end
      end
    end
  end
  # Dashboard routes (authenticated users)
  resources :dashboards do
    member do
      post :duplicate
      post :add_widget
      patch :update_layout
      delete "remove_widget/:widget_id", to: "dashboards#remove_widget", as: :remove_widget
      get "refresh_widget/:widget_id", to: "dashboards#refresh_widget", as: :refresh_widget
      patch "update_widget/:widget_id", to: "dashboards#update_widget", as: :update_widget
    end
  end

  # Static pages
  get "features", to: "pages#features"
  get "pricing", to: "pages#pricing"
  get "documentation", to: "pages#documentation"
  get "about", to: "pages#about"
  get "careers", to: "pages#careers"
  get "contact", to: "pages#contact"
  get "blog", to: "pages#blog"
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"

  # Defines the root path route ("/")
  root "pages#home"
end
