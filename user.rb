require 'set'
require 'yaml'
require 'rubygems'
require 'pivotal-tracker'

class User
  class << self; attr_accessor :save_location; end
  
  attr_accessor :current_story
  attr_accessor :current_tracker
  attr_reader :token
  attr_reader :current_project
  attr_reader :projects

  @@users = {}

  def initialize(nick)
    @projects = Set.new
    @nick = nick
  end

  def self.for_nick(nick)
    user = @@users[nick] || YAML.load_file(self.save_filename(nick)) rescue User.new(nick)
    @@users[nick] ||= user
  end

  def token=(token)
    @token = token
    save
  end

  def current_project_id=(project_id)
    @current_tracker = PivotalTracker.new project_id, @token
    @current_project = @current_tracker.project
    @projects << @current_project
    save
  end

  def current_story_id=(id)
    @current_story = @current_tracker.find_story(id)
    save
  end
  
  def create_story(attributes)
    @current_story = @current_tracker.create_story Story.new(attributes)
    save
    @current_story
  end    

  def update_story(attributes)
    attributes.each do |key, value|
      @current_story.send "#{key}=".to_sym, value
    end

    @current_tracker.update_story @current_story
  end

  def find_stories(criteria)
    @current_tracker.find criteria
  end
  
  def self.save_filename(nick)
    File.join self.save_location, "#{nick}.yml"
  end

  def save
    File.open(User.save_filename(@nick), 'w') do |f|
      f.print self.to_yaml
    end
  end
end
