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
    puts "adapter #{config[:adapter]} not supported"
  end
end

# Creates the sample schema in the database specified by the give 
# Configuration object
def create_sample_schema(config)
  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection
  
  ActiveRecord::Schema.define do
    create_table :scanner_records do |t|
      t.column :name, :string, :null => false
    end rescue nil

    add_index :scanner_records, :name, :unique rescue nil

    create_table :scanner_left_records_only do |t|
      t.column :name, :string, :null => false
    end rescue nil

    # also used in Scanner rspec
    create_table :extender_combined_key, :id => false do |t|
      t.column :first_id, :integer
      t.column :second_id, :integer
    end rescue nil 
    
    ActiveRecord::Base.connection.execute(<<-end_sql) rescue nil
      ALTER TABLE extender_combined_key ADD CONSTRAINT extender_combined_key_pkey 
	PRIMARY KEY (first_id, second_id)
    end_sql

    create_table :extender_inverted_combined_key, :id => false do |t|
      t.column :first_id, :integer
      t.column :second_id, :integer
    end rescue nil 
    
    ActiveRecord::Base.connection.execute(<<-end_sql) rescue nil
      ALTER TABLE extender_inverted_combined_key 
        ADD CONSTRAINT extender_inverted_combined_key_pkey 
	PRIMARY KEY (second_id, first_id)
    end_sql

    # also used in Scanner rspec
    create_table :extender_without_key, :id => false do |t|
      t.column :first_id, :integer
      t.column :second_id, :integer
    end rescue nil 
    
    create_table :extender_one_record do |t|
      t.column :name, :string
    end rescue nil
    
    create_table :extender_no_record do |t|
      t.column :name, :string
    end rescue nil
    
    create_table :extender_type_check do |t|
      t.column :decimal, :decimal
      t.column :timestamp, :timestamp
      t.column :byteea, :binary
    end rescue nil
  end
end

# Removes all tables from the sample scheme
# config: Hash of configuration values for the desired database connection
def drop_sample_schema(config)
  ActiveRecord::Base.establish_connection(config)
  ActiveRecord::Base.connection
  
  ActiveRecord::Schema.define do
    drop_table :extender_type_check rescue nil
    drop_table :extender_no_record rescue nil
    drop_table :extender_one_record rescue nil
    drop_table :extender_without_key rescue nil
    drop_table :extender_inverted_combined_key rescue nil
    drop_table :extender_combined_key rescue nil
    drop_table :scanner_left_records_only rescue nil
    drop_table :scanner rescue nil
  end  
end

# The standard ActiveRecord#create method ignores primary key attributes.
# This module provides a create method that allows manual setting of primary key values.
module CreateWithKey
  def self.included(base)
    base.extend(ClassMethods)
  end  
  
  module ClassMethods
    # The standard "create" method ignores primary key attributes
    # This method set's _all_ attributes as provided
    def create_with_key attributes
      o = new
      attributes.each do |key, value|
	o[key] = value
      end
      o.save
    end
  end
end

class ScannerRecords < ActiveRecord::Base
  include CreateWithKey
end

class ScannerLeftRecordsOnly < ActiveRecord::Base
  set_table_name "scanner_left_records_only"
  include CreateWithKey
end

class ExtenderOneRecord < ActiveRecord::Base
  set_table_name "extender_one_record"
  include CreateWithKey
end

class ExtenderTypeCheck <ActiveRecord::Base
  set_table_name "extender_type_check"
  include CreateWithKey
end

# Deletes all records and creates the records being same in left and right DB
def delete_all_and_create_shared_sample_data(connection)
  ScannerRecords.connection = connection
  ScannerRecords.delete_all
  ScannerRecords.create_with_key :id => 1, :name => 'Alice - exists in both databases'
  
  ExtenderOneRecord.connection = connection
  ExtenderOneRecord.delete_all
  ExtenderOneRecord.create_with_key :id => 1, :name => 'Alice'
  
  ExtenderTypeCheck.connection = connection
  ExtenderTypeCheck.delete_all
  ExtenderTypeCheck.create_with_key(
    :id => 1, 
    :decimal => 1.234,
    :timestamp => Time.local(2007,"nov",10,20,15,1),
    :byteea => "dummy")
end

# Reinitializes the sample schema with the sample data
def create_sample_data
  session = RR::Session.new
  
  # Create records existing in both databases
  [session.left, session.right].each do |connection|
    delete_all_and_create_shared_sample_data connection
  end

  # Create data in left table
  ScannerRecords.connection = session.left
  ScannerRecords.create_with_key :id => 2, :name => 'Bob - left database version'
  ScannerRecords.create_with_key :id => 3, :name => 'Charlie - exists in left database only'
  ScannerRecords.create_with_key :id => 5, :name => 'Eve - exists in left database only'
  
  # Create data in right table
  ScannerRecords.connection = session.right
  ScannerRecords.create_with_key :id => 2, :name => 'Bob - right database version'
  ScannerRecords.create_with_key :id => 4, :name => 'Dave - exists in right database only'
  ScannerRecords.create_with_key :id => 6, :name => 'Fred - exists in right database only'

  ScannerLeftRecordsOnly.connection = session.left
  ScannerLeftRecordsOnly.create_with_key :id => 1, :name => 'Alice'
  ScannerLeftRecordsOnly.create_with_key :id => 2, :name => 'Bob'
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
    
    desc "Rebuilds the test databases & schemas"
    task :rebuild => [:drop_schema, :drop, :create, :create_schema, :populate]
    
    desc "Create the sample schemas"
    task :create_schema do
      create_sample_schema RR::Initializer.configuration.left rescue nil
      create_sample_schema RR::Initializer.configuration.right rescue nil
    end
    
    desc "Writes the sample data"
    task :populate do
      create_sample_data
    end

    desc "Drops the sample schemas"
    task :drop_schema do
      drop_sample_schema RR::Initializer.configuration.left rescue nil
      drop_sample_schema RR::Initializer.configuration.right rescue nil
    end
  end
end