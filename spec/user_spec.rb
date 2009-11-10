require 'set'
require 'user'
require 'pivotal-tracker'

describe "The User class" do
  before :each do
    @logger = mock 'logger'
    @logger.stub! :debug
    User.logger = @logger
  end

  it "should cache users" do
    user1 = User.for_nick 'fred'
    user2 = User.for_nick 'fred'
    user1.should == user2
  end
  
  it "should have a save location" do
    User.save_location = '/tmp'
    User.save_location.should == '/tmp'
  end

  it "should have a logger" do
    User.logger = nil
  end

  it "should determine a save filename" do
    User.save_location = '/tmp'
    User.save_filename('dug').should == '/tmp/dug.yml'
  end
end

describe "A user" do
  before :each do
    User.users = {}
    @logger = mock 'logger'
    @logger.stub! :debug
    User.logger = @logger
    @user = User.for_nick 'dug'
    @the_project = mock 'project'
    @the_story_id = '9'
    @the_story = mock 'story', :id => @the_story_id
    @the_note = mock 'note'
    @the_tracker = mock 'tracker', :project => @the_project
    PivotalTracker.stub!(:new).with('2', 'fish').and_return(@the_tracker)
    @user.stub!(:save)
  end

  it "should remember a token" do
    @user.token = 'fish'
    @user.token.should == 'fish'
  end

  it "should get a project by id" do
    @user.token = "fish"
    @user.current_project_id = "2"
    @user.current_project.should == @the_project
    @user.current_tracker.should == @the_tracker
  end

  it "should set current story by id" do
    @user.current_tracker = @the_tracker
    @the_tracker.should_receive(:find_story).with('pie').and_return(@the_story)
    @user.current_story_id = 'pie'
    @user.current_story.should == @the_story
  end

  it "should update stories" do
    @user.current_tracker = @the_tracker
    @user.current_story = @the_story
    @the_story.should_receive(:name=).with('mud')
    @the_tracker.should_receive(:update_story).with(@the_story)
    @user.update_story 'name' => 'mud'
  end

  it "should create notes" do
    atts = {:text => 'I totally disagree with this.'}
    Note.stub!(:new).with(atts).and_return(@the_note)
    @user.current_tracker = @the_tracker
    @user.current_story = @the_story
    @the_tracker.should_receive(:create_note).with(@the_story_id, @the_note)
    @user.create_note atts[:text]
  end

  it "should add stories" do
    atts = {:name => 'bananas should be tasty', :story_type => 'feature'}
    Story.stub!(:new).with(atts).and_return(@the_story)
    @user.current_tracker = @the_tracker
    @the_tracker.should_receive(:create_story).with(@the_story).and_return(@the_story)
    story = @user.create_story atts
    story.should == @the_story
  end

  it "should find stories" do
    stories = [1,2,3]
    criteria = {:state => 'finished'}
    @user.current_tracker = @the_tracker
    @the_tracker.should_receive(:find).with(criteria).and_return(stories)
    @user.find_stories(criteria).should == stories
  end

  it "should list projects" do
    tracker3 = mock 'tracker3', :project => 3
    tracker4 = mock 'tracker4', :project => 4
    PivotalTracker.stub!(:new).with('3', 'fish').and_return(tracker3)
    PivotalTracker.stub!(:new).with('4', 'fish').and_return(tracker4)
    @user.token = 'fish'
    @user.current_project_id = "2"
    @user.current_project_id = "3"
    @user.current_project_id = "4"
    @user.projects.should == Set.new([@the_project,3,4])
  end
end

