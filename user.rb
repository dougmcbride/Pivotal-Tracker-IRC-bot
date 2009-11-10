require 'set'
require 'yaml'
require 'rubygems'
require 'pivotal-tracker'

class User
  class << self
    attr_accessor :save_location
    attr_accessor :users
    attr_accessor :logger
  end
  
  attr_accessor :current_story
  attr_accessor :current_tracker
  attr_reader :token
  attr_reader :current_project
  attr_reader :projects

  self.users = {}

  def initialize(nick)
    @projects = Set.new
    @nick = nick
  end

  def self.for_nick(nick)
    user = self.users[nick] || YAML.load_file(self.save_filename(nick)) || User.new(nick) rescue User.new(nick)
    self.logger.debug "new user = #{user.inspect}"
    self.users[nick] ||= user
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

  def to_yaml
    <<EOT
--- !ruby/object:User 
current_project: &id001 !ruby/object:Project 
  id: 38441
  iteration_length: 1
  name: zbot
  point_scale: "0,1,2,3"
  week_start_day: Monday
current_story: !ruby/object:Story 
  accepted_at: 
  created_at: 2009-11-10T02:22:47-08:00
  current_state: unscheduled
  description: ""
  estimate: 
  id: 1686672
  iteration: 
  labels: 
  name: i like fish
  owned_by: 
  requested_by: Doug McBride
  story_type: bug
  url: http://www.pivotaltracker.com/story/show/1686672
current_tracker: !ruby/object:PivotalTracker 
  base_url: http://www.pivotaltracker.com/services/v2
  project_id: "38441"
  token: 901ef633edabeab50299ae72a9b459ad
nick: dug
projects: !ruby/object:Set 
  hash: 
    *id001: true
    !ruby/object:Project ? 
      id: 38441
      iteration_length: 1
      name: zbot
      point_scale: "0,1,2,3"
      week_start_day: Monday
    : true

token: 901ef633edabeab50299ae72a9b459ad
EOT
  end
end
