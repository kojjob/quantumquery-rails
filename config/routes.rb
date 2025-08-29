Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions"
  }
  
  # Two-Factor Authentication
  namespace :users do
    resource :two_factor_authentication, only: [:show] do
      post :enable
      delete :disable
      post :regenerate_backup_codes
    end
  end
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

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
