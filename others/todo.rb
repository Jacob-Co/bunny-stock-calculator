require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

before do
  @storage = SessionPersistence.new(session)
end

class SessionPersistence
  def initialize(session)
    @session = session
    @session[:lists] ||= []
  end

  def find_list(id)
    @session[:lists].find {|list| list[:id] == id}
  end

  def all_lists
    @session[:lists]
  end

  def list_exists?(name)
    @session[:lists].any? {|list| list == name}
  end
end

helpers do
  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition {|list| all_todos_complete?(list)}

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos, &block)
    complete_todos, incomplete_todos = todos.partition {|todo| todo[:completed]}

    incomplete_todos.each(&block)
    complete_todos.each(&block)
  end

  def all_todos_complete?(list)
    all_todos = list[:todos]
    return false if all_todos.empty?
    all_todos.each {|todo| return false if todo[:completed] != true}
    true
  end

  def tasks_finished_over_unfinished(list)
    all_todos = list[:todos]
    number_of_todos = all_todos.size
    finished_todos = all_todos.select{|todo| !(todo[:completed])}.size
    "#{finished_todos} / #{number_of_todos}"
  end

  def list_class(list)
    return 'complete' if all_todos_complete?(list)
  end
end

def next_list_id(lists)
  max = lists.map { |list| list[:id] }.max || 0
  max + 1
end

def next_todo_id(todos)
  max = todos.map { |todo| todo[:id] }.max || 0
  max + 1
end

get "/" do
  redirect "/lists"
end


# See all existing lists
get "/lists" do
  @lists = @storage.all_lists
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Error messages for creating lists
# Return an error message if the name is invalid.
# Return nil if valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    'List name must be between 1 and 100 characters.'
  elsif @storage.list_exists?(name)
    'List name already exists.'
  end
end

def load_list(id)
  list = @storage.find_list(id)
  return list if list

  session[:error] = "The specified list was not found."
  redirect "/lists"
end

# Create a new list
post "/lists/new" do
  list_name = params[:list_name].strip
  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    id = next_list_id(@storage.all_lists)
    @storage.all_lists << {id: id, name: list_name, todos: []}
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# Got to edit list page
get /\/lists\/([0-9]+)\/edit/ do
  @list_order = params[:captures].first.to_i
  @list = load_list(@list_order)
  erb :edit_list, layout: :layout
end

# Go to a list page for more info
get /\/lists\/([0-9]+)/ do
  @list_order = params[:captures].first.to_i
  @list = load_list(@list_order)
  erb :list_info, layout: :layout
end

# Rename a list
post /\/lists\/([0-9]+)\/rename/ do
  @list_order = params[:captures].first.to_i
  @list = load_list(@list_order)

  original_name = @list[:name]
  new_name = params[:list_name].strip

  error = error_for_list_name(new_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    session[:success] = "The list '#{original_name}' has been successfully edited to '#{new_name}'."
    @list[:name] = new_name
    redirect "/lists/#{@list_order}"
  end
end

# Delete a todo list
post /\/lists\/([0-9]+)\/delete/ do
  list_order = params[:captures].first.to_i
  deleted_list = @storage.all_lists.reject! { |list| list[id] == list_order}

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    session[:success] = "List '#{deleted_list}' was successfully deleted."
    redirect "/lists"
  end
end

# Error messages for creating lists
# Return an error message if the name is invalid.
# Return nil if valid.
def error_for_todo(name)
  'To do name must be between 1 and 100 characters.' if !(1..100).cover? name.size
end

# Delete a todo
post /\/lists\/([0-9]+)\/todo\/([0-9]+)\/delete/ do
  list_order = params[:captures].first.to_i
  todo_id= params[:captures][1].to_i
  list = load_list(list_order)
  todos = list[:todos]

  todos.reject! { |todo| todo[:id] == todo_id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    session[:success] = "A to do was successfully deleted."
    redirect "/lists/#{list_order}"
  end
end

# Check or uncheck a to do item in the list info page
post /\/lists\/([0-9]+)\/todo\/([0-9]+)/ do
  list_order = params[:captures].first.to_i
  todo_id = params[:captures][1].to_i

  list = load_list(list_order)
  todo = list[:todos].find { |todo| todo[:id] == todo_id }
  todo_status = !(params[:completed] == 'true') #toggle

  todo[:completed] = todo_status

  session[:success] = "#{todo[:name]} has been marked as completed" if todo[:completed]
  session[:error] = "#{todo[:name]} has been unmarked" unless todo[:completed] # not an error, just a stylistic choice
  redirect "/lists/#{list_order}"
end

# mark all tasks complete
post /\/lists\/([0-9]+)\/complete_all/ do
  @list_order = params[:captures].first.to_i
  @list = load_list(@list_order)
  all_todos = @list[:todos]
  if all_todos.empty?
    session[:error] = "There are currently no to do's to mark."
    erb :list_info
  else
    all_todos.each {|todo| todo[:completed] = true}
    session[:success] = "All to do's are marked as finished."
    redirect "/lists/#{@list_order}"
  end
end

# Add a new todo to a list
post /\/lists\/([0-9]+)\/todo/ do
  @list_order = params[:captures].first.to_i
  @list = load_list(@list_order)

  new_todo = params[:todo].strip

  error = error_for_todo(new_todo)
  if error
    session[:error] = error
    erb :list_info, layout: :layout
  else
    id = next_todo_id(@list[:todos])
    session[:success] = "'#{new_todo}' added to '#{@list[:name]}'."
    @list[:todos] << {id: id, name: new_todo, completed: false}
    redirect "/lists/#{@list_order}"
  end
end
