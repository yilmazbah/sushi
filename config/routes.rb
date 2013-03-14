SushiFabric::Application.routes.draw do
  root :to => "home#index"
  
  get "run_script/run_sample"
  
  match "/data_set/create" => "data_set#create"
  match "/data_set/delete" => "data_set#delete"
  
  devise_for :users
  get 'run_script', :to => 'run_script#index', :as => :user_root
  
  resources :run_script do
    collection do
      post :run_fastqc
      post :run_sample
      post :run_sample2
      post :index
      post :confirm
      post :set_parameters
      post :run_application
      post :submit_job
    end
  end
  
  resources :job_monitoring do
    collection do
      post :index
      get :print_log
      get :print_script
    end
  end
  
  resources :data_list do
    collection do
      post :index
      get :add
      get :delete
    end
  end
  
  resources :data_set do
    collection do
      post :index
      get :edit
      post :add
      post :delete
      post :add_or_delete
      post :create
    end
  end
  
  resources :project, :only => [:index, :show]
  resources :sample, :only => [:show]
  resources :extract, :only => [:show]
  
  match "/resource/add_to_basket/:id" => "resource#add_to_basket"
  match "/resource/remove_from_basket/:id" => "resource#remove_from_basket"
  
  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end