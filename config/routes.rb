Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Public share links
  get 'shared/:token', to: 'share_links#show', as: :shared_analysis
  post 'shared/:token/authenticate', to: 'share_links#authenticate', as: :authenticate_shared_analysis
  
  # Team invitations
  get 'invitations/:token', to: 'team_memberships#accept_invitation', as: :accept_invitation
  
  # Authenticated routes
  authenticate :user do
    resources :datasets do
      member do
        post :analyze
      end
      resources :comments, only: [:index, :create, :update, :destroy]
    end
    
    resources :analysis_requests, only: [:index, :show, :destroy] do
      member do
        get :export
      end
      resources :share_links, only: [:create, :update, :destroy]
      resources :comments, only: [:index, :create, :update, :destroy]
    end
    
    resources :scheduled_reports do
      member do
        patch :enable
        patch :disable
        post :run_now
      end
    end
    
    resources :organizations, only: [] do
      resources :team_memberships, only: [:index, :create, :update, :destroy] do
        member do
          post :resend_invitation
        end
      end
    end
    
    get "dashboard", to: "dashboard#index"
  end

  # Defines the root path route ("/")
  root "pages#home"
end
