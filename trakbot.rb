require 'optparse'
require 'pp'
require 'yaml'

require 'rubygems'
require 'pivotal-tracker'

require 'chatbot'
require 'common_actions'
require 'user'



options = {
  :channel => 'traktest',
  :full => 'Pivotal Tracker IRC bot',
  :nick => 'trackbot',
  :port => '6667',
  :server => 'irc.freenode.net',
  :logging => :warn,
  :storage_location => '.'
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-c', '--channel NAME', 'Specify IRC channel to /join. (test)') {|options[:channel]|}
  opts.on('-f', '--full-name NICK', "Specify the bot\'s IRC full name. (#{options[:full]})") {|options[:full]|}
  opts.on('-n', '--nick NICK', "Specify the bot\'s IRC nick. (#{options[:nick]})") {|options[:nick]|}
  opts.on('-s', '--server HOST', 'Specify IRC server hostname. (irc.freenode.net)') {|options[:server]|}
  opts.on('-p', '--port NUMBER', Integer, 'Specify IRC port number. (6667)') {|options[:port]|}
  opts.on('-l', '--logging LEVEL', [:debug, :info, :warn, :error, :fatal], 'Logging level (debug, info, warn, error, fatal) (warn)') {|options[:logging]|}
  opts.on('-y', '--storage-file FILENAME', 'The directory the bot will use to store its state files in. (.)') {|options[:storage_location]|}

  opts.on_tail('-h', '--help', 'Display this screen') {puts opts; exit}
end

optparse.parse!


class ChoreFinishedError < StandardError; end
class NoSearchError < StandardError; end

class Trakbot < Chatbot
  include CommonActions

  def initialize(options)
    super options[:nick], options[:server], options[:port], options[:full]
    @options = options

    @help = [
      "help: this",
      "help short: get list of command abbreviations",
      "comment|note <text>: Add a comment to the story",
      "deliver finished: Deliver (and display) all finished stories",
      "find <text>: Find stories in the project that match the search criteria in <text>.",
      "finished: List finished stories in the project",
      "initials [nick] <initials>: Teach me your nick's  (or another nick's) Pivotal Tracker initials",
      "list found: List results of the last find (even if it's long).",
      "new feature|chore|bug|release <name>: Create a story in the project's Icebox with given name",
      "project: Set your current project to the last mentioned project",
      "project <id>|<partial name>: Set your current project",
      "projects: List all known projects",
      "status: Show current project and story",
      "story: Set your current story to the last mentioned story",
      "story <id|list-index>: Set your current story",
      "story current_state unstarted|started|finished|delivered|rejected|accepted: Update the story",
      "story name|estimate <text>: Update the story",
      "story story_type feature|bug|chore|release: Update the story",
      "token <token>: Teach me your nick's Pivotal Tracker API token",
      "work [user]: Show what stories [user] is working on (default is you)"
    ]

    @help_short = [
      ".h = help",
      ".? = status",
      ".c <text> = comment <text>",
      ".f <text> = find <text>",
      ".l = list found",
      ".n(f|c|b|r) <name> = new feature|chore|bug|release <name>",
      ".p = project",
      ".p <id|partial name> = project <id>|<partial name>",
      ".ps = projects",
      ".s = story",
      ".s <id|list-index> = story <id|list-index>",
      ".s(n|e) <text> = story name|estimate <text>",
      ".se <estimate> = story estimate <estimate>",
      ".sn <name> = story name <name>",
      ".ss u|s|f|d|r|a = story current_state <state>",
      ".st <type> = story story_type feature|bug|chore|release",
      ".w [user] = work [user]"
    ]

    @logger.level = eval "Logger::#{options[:logging].to_s.upcase}"

    User.save_location = options[:storage_location]
    User.logger = @logger

    # The channel to join.
    add_room('#' + options[:channel])

    nick = options[:nick]

    send_help = lambda do |nick, event, match|
      reply event, "#{nick}, I'm sending you the command list privately (it's long)..."
      @help.each {|l| reply_privately event, l}
    end

    send_short_help = lambda do |nick, event, match|
      reply event, "#{nick}, I'm sending you the list privately (it's long)..."
      @help_short.each {|l| reply_privately event, l}
    end

    project_set_by_id = lambda do |nick, event, match|
      user = User.for_nick nick
      user.current_project_id = match[1]
      reply event, "#{nick}, you're on #{user.current_project.name}."
      @last_project = user.current_project
    end

    project_set_by_name = lambda do |nick, event, match|
      user = User.for_nick nick
      projects = user.projects.select{|p| p.name.downcase.include? match[1].downcase}

      if projects.empty?
        reply event, "#{nick}, I couldn't find a project with '#{match[1]}' in its name."
      elsif projects.size > 1
        reply event, "#{nick}, you'll need to be a bit more specific. I found #{projects.map{|p| p.name} * ', '}."
      else
        user.current_project_id = projects.first.id
        reply event, "#{nick}, you're on #{user.current_project.name}."
        @last_project = user.current_project
      end
    end

    set_token = lambda do |nick, event, match|
      user = User.for_nick nick
      user.token = match[1]
      reply event, one_of(["Got it, #{nick}.", "Gotcha, #{nick}.", "All righty, #{nick}!"])
    end

    set_initials_self = lambda do |nick, event, match|
      user = User.for_nick nick
      user.initials = match[1]
      reply event, "Got it, #{nick}."
    end

    set_initials_other = lambda do |nick, event, match|
      user = User.for_nick match[1]
      user.initials = match[2]
      reply event, "Got it, #{nick}."
    end

    create_story = lambda do |nick, event, match|
      user = User.for_nick nick
      story = user.create_story :name => match[2], :story_type => match[1]
      reply event, "Added story #{story.id}"
      @last_story = story
      @last_project = user.current_project
    end

    create_story_short = lambda do |nick, event, match|
      abbrev_map = {:f => :feature, :c => :chore, :b => :bug, :r => :release}
      create_story.call nick, event, [match[0], abbrev_map[match[1].to_sym].to_s, match[2]]
    end

    set_story_from_list = lambda do |nick, event, match|
      begin
        user = User.for_nick nick
        fail NoSearchError unless user.found_stories
        fail IndexError unless story = user.found_stories[match[1].to_i - 1]
        user.current_story_id = story.id
        reply event, "#{nick}'s current story: #{user.current_story.name}"
        @last_story = user.current_story
        @last_project = user.current_project
      rescue NoSearchError
        reply event, "#{nick}, you haven't done a search, and that's too short to be a Pivotal Tracker id."
      rescue IndexError
        reply event, "#{nick}, that story index is too big, your last search only had #{user.found_stories.size} stories in it."
      rescue RestClient::ResourceNotFound
        reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{user.current_project.name})?"
      end
    end

    set_story_from_id = lambda do |nick, event, match|
      begin
        user = User.for_nick nick
        user.current_story_id = match[1]
        reply event, "#{nick}'s current story: #{user.current_story.name}"
        @last_story = user.current_story
        @last_project = user.current_project
      rescue RestClient::ResourceNotFound
        reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{user.current_project.name})?"
      end
    end

    @update_story = lambda do |nick, event, match|
      begin
        user = User.for_nick nick
        fail ChoreFinishedError if user.current_story.story_type == 'chore' and match[1] == 'current_state' and match[2] == 'finished'
        user.update_story match[1] => match[2]
        reply event, "#{user.current_story.id}: #{match[1]} --> #{match[2]}"
        @last_story = user.current_story
        @last_project = user.current_project
      rescue RestClient::ResourceNotFound
        reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{user.current_project.name})?"
      rescue ChoreFinishedError
        reply event, "#{nick}, chores cannot be 'finished'. You probably want 'accepted'."
      end
    end

    def update_story_attribute(attribute, nick, event, match)
      @update_story.call(nick, event, [match[0], attribute.to_s, match[1]])
    end

    update_story_name = lambda do |nick, event, match|
      update_story_attribute(:name, nick, event, match)
    end

    update_story_type = lambda do |nick, event, match|
      update_story_attribute(:story_type, nick, event, match)
    end

    update_story_state = lambda do |nick, event, match|
      abbrev_map = {
        'u' => :unstarted,
        's' => :started,
        'f' => :finished,
        'd' => :delivered,
        'r' => :rejected,
        'a' => :accepted
      }
      update_story_attribute(:current_state, nick, event, [match[0], abbrev_map[match[1].slice(0,1)].to_s])
    end

    update_story_estimate = lambda do |nick, event, match|
      update_story_attribute(:estimate, nick, event, match)
    end

    create_note = lambda do |nick, event, match|
      begin
        user = User.for_nick nick
        user.create_note match[1]
        reply event, "Ok, #{nick}"
      rescue RestClient::ResourceNotFound
        reply event, "#{nick}, I couldn't find that one. Maybe it's not in your current project (#{user.current_project.name})?"
      end
    end

    find_stories = lambda do |nick, event, match|
      user = User.for_nick nick
      list_stories user.find_stories(match[1]), event, user
    end

    find_finished_stories = lambda do |nick, event, match|
      user = User.for_nick nick
      list_stories user.find_stories(:state => 'finished'), event, user
    end

    find_work_self = lambda do |nick, event, match|
      user = User.for_nick nick
      if user.initials
        list_stories user.find_stories(:owned_by => user.initials, :state => 'started'), event, user
      else
        reply event, "I need your Pivotal Tracker initials please: 'initials <initials>'"
      end
    end

    find_work_other = lambda do |nick, event, match|
      user = User.for_nick nick
      user2 = User.for_nick match[1]
      if user2.initials
        list_stories user.find_stories(:owned_by => user2.initials, :state => 'started'), event, user
      else
        reply event, "I need #{match[1]}'s Pivotal Tracker initials please: 'initials #{match[1]} <initials>'"
      end
    end

    list_found = lambda do |nick, event, match|
      user = User.for_nick nick
      list_stories user.found_stories, event, user, true
    end

    deliver_finished = lambda do |nick, event, match|
      user = User.for_nick nick
      stories = user.current_tracker.deliver_all_finished_stories
      if stories.empty?
        reply event, "No finished stories in project :("
      else
        reply event, "Delivered #{stories.size} stories:"
        list_stories stories, event, user
      end
    end

    list_projects = lambda do |nick, event, match|
      user = User.for_nick nick
      user.projects.sort_by{|p| p.name.dwncase}.each_with_index do |project, i|
        reply event, "#{i+1}) #{project.id}: #{project.name}"
      end
    end

    show_state = lambda do |nick, event, match|
      user = User.for_nick nick
      reply event, "#{nick}'s project: #{user.current_project.name}" if user.current_project
      reply event, "#{nick}'s story: #{user.current_story.story_type.capitalize} #{user.current_story.id}: #{user.current_story.name}" if user.current_story
    end

    set_last_story = lambda do |nick, event, match|
      user = User.for_nick nick
      if @last_story
        user.current_story = @last_story
        user.current_project_id = @last_project.id
        reply event, "#{nick}'s current story: #{user.current_story.name}"
      else
        reply event, "No last-mentioned story to use, sorry."
      end
    end

    set_last_project = lambda do |nick, event, match|
      user = User.for_nick nick
      if @last_project
        user.current_project_id = @last_project.id
        reply event, "#{nick}'s current project: #{user.current_project.name}"
      else
        reply event, "No last-mentioned project to use, sorry."
      end
    end


    add_trackbot_actions({
      %w[token (\S+)] => set_token,
      %w[initials (\w+)] => set_initials_self,
      %w[initials (\w+) (\w+)] => set_initials_other,
      %w[(?:new|add) (feature|chore|bug|release) (.+)] => create_story,
      %w[project] => set_last_project,
      %w[project (\d+)] => project_set_by_id,
      %w[project ([a-z]+.*)] => project_set_by_name,
      %w[story] => set_last_story,
      %w[story (\d{1,3})] => set_story_from_list,
      %w[story (\d{4,})] => set_story_from_id,
      %w[story (story_type|estimate|current_state|name) (.+)] => @update_story,
      %w[(?:comment|note) (.+)] => create_note,
      %w[find (.+)] => find_stories,
      %w[finished] => find_finished_stories,
      %w[work] => find_work_self,
      %w[work (\w+)] => find_work_other,
      %w[(?:y\w*|list found)] => list_found,
      %w[deliver finished] => deliver_finished,
      %w[projects] => list_projects,
      %w[status] => show_state,
      %w[help] => send_help,
      %w[help short] => send_short_help
    })

    add_short_tracker_actions({
      %w[h] => send_help,
      %w[p] => set_last_project,
      %w[p (\d+)] => project_set_by_id,
      %w[p ([a-z]+.*)] => project_set_by_name,
      %w[ps] => list_projects,
      %w[s] => set_last_story,
      %w[s (\d{1,3})] => set_story_from_list,
      %w[s (\d{4,})] => set_story_from_id,
      %w[(?:sn|m) (\w+)] => update_story_name,
      %w[(?:st|t) (\w+)] => update_story_type,
      %w[(?:ss|a) (\w).*] => update_story_state,
      %w[(?:se|e) (\w+)] => update_story_estimate,
      %w[c (.+)] => create_note,
      %w[(?:/|f) (.+)] => find_stories,
      %w[l] => list_found,
      %W[\\?] => show_state,
      %w[n(f|c|b|r) (.+)] => create_story_short,
      %w[w] => find_work_self,
      %w[w (\w+)] => find_work_other
    })
  end

  def list_stories(stories, event, user, force = false)
    too_big = (!force and stories.size > 4 and event.channel.match(/^#/))

    message = "Found #{stories.size} matching #{user.current_project.name} stories."
    message += " Want me to list them in here?" if too_big
    reply event, message

    unless too_big
      stories.each_with_index do |story, i|
        reply event, "#{i+1}) #{story.story_type.capitalize} #{story.id}: #{story.name}"
      end
    end
  end

  def add_trackbot_actions(action_hash)
    action_hash.each do |cmd, action|
      add_actions %r|^#{([@options[:nick] + ','] + cmd) * '\\s+'}$| => action
    end
  end

  def add_short_tracker_actions(action_hash)
    action_hash.each do |cmd, action|
      add_actions %r|^\.#{cmd * '\\s*'}$| => action
    end
  end
end


Trakbot.new(options).start
