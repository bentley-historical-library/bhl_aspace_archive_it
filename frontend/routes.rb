ArchivesSpace::Application.routes.draw do

  [AppConfig[:frontend_proxy_prefix], AppConfig[:frontend_prefix]].uniq.each do |prefix|

    scope prefix do
      match('/plugins/archive_it' => 'archive_it#index', :via => [:get])
      match('/plugins/archive_it/:id/download_marc' => 'archive_it#download_marc', :via => [:get])
      match('/plugins/archive_it/import' => 'archive_it#import', :via => [:post])
    end
  end
end