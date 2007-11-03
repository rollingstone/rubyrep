$LOAD_PATH.unshift File.dirname(__FILE__) + "../lib/rubyrep"
require 'rake'
require 'rubyrep'
require File.dirname(__FILE__) + '/../config/test_config'

# Creates the databases in the given Configuration object
def create_database(config)
  begin
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection
  rescue
    case config[:adapter]
    when 'postgresql'
      `createdb "#{config[:database]}" -E utf8`
    else
      puts "adapter #{config[:adapter]} not supported"
    end
  else
    puts "database #{config[:database]} already exists"
  end
end

# Drops the databases in the given Configuration object
def drop_database(config)
  case config[:adapter]
  when 'postgresql'
    `dropdb "#{config[:database]}"`
  else
    puts "database #{config[:database]} already exists"
  end
end

# Creates the sample scheme in the database specified by the give 
# Configuration object
def create_sample_scheme(config)
  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection
  
  ActiveRecord::Schema.define do
    create_table :authors do |t|
      t.column :name, :string, :null => false
    end rescue nil

    add_index :authors, :name, :unique rescue nil

    create_table :posts do |t|
      t.column :author_id, :integer, :null => false
      t.column :subject, :string
      t.column :body, :text
      t.column :private, :boolean, :default => false
    end rescue nil

    add_index :posts, :author_id rescue nil
  end
end

def drop_sample_scheme(config)
  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection
  
  ActiveRecord::Schema.define do
    drop_table :authors rescue nil
    drop_table :posts rescue nil
  end  
end

namespace :db do
  namespace :test do
    
    desc "Creates the test databases"
    task :create do
      create_database RR::Initializer.configuration.left rescue nil
      create_database RR::Initializer.configuration.right rescue nil
    end
    
    desc "Drops the test databases"
    task :drop do
      drop_database RR::Initializer.configuration.left rescue nil
      drop_database RR::Initializer.configuration.right rescue nil
    end
    
    desc "Rebuilds the test databases & schemes"
    task :rebuild => [:drop_scheme, :drop, :create, :create_scheme]
    
    desc "Create the sample schemes"
    task :create_schema do
      create_sample_scheme RR::Initializer.configuration.left rescue nil
      create_sample_scheme RR::Initializer.configuration.right rescue nil
    end

    desc "Drops the sample schemes"
    task :drop_schema do
      drop_sample_scheme RR::Initializer.configuration.left rescue nil
      drop_sample_scheme RR::Initializer.configuration.right rescue nil
    end
  end
end