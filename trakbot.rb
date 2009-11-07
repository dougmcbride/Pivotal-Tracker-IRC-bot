require 'optparse'
require 'chatbot'
require 'rubygems'
gem 'jsmestad-pivotal-tracker'
require 'pivotal-tracker'
require 'pp'
require 'yaml'

require 'common_actions'


options = {
  :channel => 'traktest',
  :full => 'Pivotal Tracker IRC bot',
  :nick => 'trakbot',
  :port => '6667',
  :server => 'irc.freenode.net',
  :logging => :warn,
  :storage_file => 'state.yml'
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-u', '--username USERNAME', 'Specify rifftrax.com username.') {|options[:username]|}
  opts.on('-w', '--password PASSWORD', 'Specify rifftrax.com password.') {|options[:password]|}
  opts.on('-c', '--channel NAME', 'Specify IRC channel to /join. (test)') {|options[:channel]|}
  opts.on('-f', '--full-name NICK', 'Specify the bot\'s IRC full name. (iRiff report bot)') {|options[:full]|}
  opts.on('-n', '--nick NICK', 'Specify the bot\'s IRC nick. (riffbot)') {|options[:nick]|}
  opts.on('-s', '--server HOST', 'Specify IRC server hostname. (irc.freenode.net)') {|options[:server]|}
  opts.on('-p', '--port NUMBER', Integer, 'Specify IRC port number. (6667)') {|options[:port]|}
  opts.on('-l', '--logging LEVEL', [:debug, :info, :warn, :error, :fatal], 'Logging level (debug, info, warn, error, fatal) (warn)') {|options[:logging]|}
  opts.on('-y', '--storage-file FILENAME', 'The file trakbot will use to store its state. (storage.yml)') {|options[:storage_file]|}

  #opts.on('-i', '--interval MINUTES', Integer, 'Number of minutes to sleep between checks (10)') do |interval|
    #fail "Interval minimum is 5 minutes." unless interval >= 5
    #options[:interval] = interval
  #end

  opts.on_tail('-h', '--help', 'Display this screen') {puts opts; exit}
end

optparse.parse!

class Hash
  # from http://snippets.dzone.com/user/dubek
  # Replacing the to_yaml function so it'll serialize hashes sorted (by their keys)
  #
  # Original function is in /usr/lib/ruby/1.8/yaml/rubytypes.rb
  def to_yaml( opts = {} )
    YAML::quick_emit( object_id, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        sort.each do |k, v|   # <-- here's my addition (the 'sort')
          map.add( k, v )
        end
      end
    end
  end
end

class Symbol
  def <=>(a)
    self.to_s <=> a.to_s
  end
end

class Trakbot < Chatbot
  include CommonActions

  def initialize(options)
    super options[:nick], options[:server], options[:port], options[:full]
    @options = options

    @help = [
      "help: this",
      "token <token>: Teach trakbot your nick's Pivotal Tracker API token",
      "project <id>: Set your current project",
      "projects: List your known projects",
      "story <id>: Set your current story",
      "story name|estimate <text>: Update story",
      "story story_type feature|bug|chore|release: Update story",
      "story current_state unstarted|started|finished|delivered|rejected|accepted: Update story",
      "finished: List finished stories in project",
      "deliver finished: Deliver (and display) all finished stories",
      "new feature|chore|bug|release <name>: Create a story in the Icebox with given name",
    ]

    @logger.level = eval "Logger::#{options[:logging].to_s.upcase}"

    load_state
    @tracker = {}

    # The channel to join.
    add_room('#' + options[:channel])

    nick = options[:nick]

    add_actions({
      %w[token (\S+)].to_regexp =>
      lambda do |nick, event, match|
        user = get_user_for_nick nick
        user[:token] = match[1]
        save_state
        reply event, "Got it, #{nick}."
      end,

      %w[(?:new|add) (feature|chore|bug|release) (.+)].to_regexp =>
      lambda do |nick, event, match|
        tracker = current_tracker_for nick
        story = tracker.create_story Story.new(:name => match[2], :story_type => match[1])
        reply event, "Added story #{story.id}"
      end,

      %w[project (\S+)].to_regexp =>
      lambda do |nick, event, match|
        user = get_user_for_nick(nick)
        user[:projects][match[1]] ||= {}
        tracker = get_tracker nick, match[1]
        user[:current_project] = match[1]
        save_state
        reply event, "#{nick}, you're on #{tracker.project.name}."
      end,

      %w[story (\S+)].to_regexp =>
      lambda do |nick, event, match|
        begin
          user = get_user_for_nick nick
          tracker = current_tracker_for nick
          user[:current_story] = match[1]
          save_state
          reply event, "#{nick}'s current story: #{tracker.find_story(match[1]).name}"
        rescue RestClient::ResourceNotFound
          reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{tracker.project.name})?"
        end
      end,

      %w[story (story_type|estimate|current_state|name) (.+)].to_regexp =>
      lambda do |nick, event, match|
        begin
          user = get_user_for_nick nick
          tracker = current_tracker_for nick
          story = tracker.find_story(current_story_for nick)
          story.send "#{match[1]}=".to_sym, match[2]
          tracker.update_story story
        rescue RestClient::ResourceNotFound
          reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{tracker.project.name})?"
        end
      end,

      %w[finished].to_regexp =>
      lambda do |nick, event, match|
        tracker = current_tracker_for nick
        stories = tracker.find :state => 'finished'
        reply event, "There are #{stories.size} finished stories."

        #reply(event, stories.map{|s| "#{s.story_type.capitalize} #{s.id}: #{s.name}"}.join("\r"))

        stories.each_with_index do |s, i|
          reply event, "#{i+1}) #{s.story_type.capitalize} #{s.id}: #{s.name}"
        end
      end,

      %w[deliver finished].to_regexp =>
      lambda do |nick, event, match|
        tracker = current_tracker_for nick
        stories = tracker.deliver_all_finished_stories

        if stories.empty?
          reply event, "No finished stories in project :("
        else
          reply event, "Delivered #{stories.size} stories:"
          stories.each_with_index {|s,i| reply event, "#{i+1}) #{s.story_type.capitalize} #{s.id}: #{s.name}"}
        end
      end,

      %w[projects].to_regexp =>
      lambda do |nick, event, match|
        get_user_for_nick(nick)[:projects].keys.each do |p|
          reply event, "#{p}: " + get_tracker(nick, p).project.name
        end
      end,

      %w[help].to_regexp =>
      lambda do |nick, event, match|
        @help.each {|l| reply event, l}
      end
    })
  end

  def get_user_for_nick(nick)
    @state[:users][nick] ||= {:projects => {}}
  end

  def get_tracker(nick, project_id)
    @tracker["#{nick}.#{project_id}"] ||= PivotalTracker.new project_id, @state[:users][nick][:token]
  end

  def current_tracker_for(nick)
    get_tracker nick, get_user_for_nick(nick)[:current_project]
  end

  def current_story_for(nick)
      get_user_for_nick(nick)[:current_story]
  end

  def save_state
    @logger.debug "Saving state: #{@state.pretty_inspect.chomp}"
    File.open(@options[:storage_file], 'w') {|f| f.print @state.to_yaml}
  end

  def load_state
    if File.exists? @options[:storage_file]
      @logger.info "Loading state from #{@options[:storage_file]}"
      @state = YAML::load File.read(@options[:storage_file])
      @logger.debug "Loaded state: #{@state.pretty_inspect}"
    else
      @logger.warn "Storage file not found, starting a new one at #{@options[:storage_file]}"
      @state = {
        :users => {}
      }
      save_state
    end
  end
end

eval <<EOT
class Array
  def to_regexp
    %r|^\#{(['#{options[:nick]},'] + self) * '\\s+'}$|
  end
end
EOT

Trakbot.new(options).start
