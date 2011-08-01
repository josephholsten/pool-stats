require 'sinatra'
require 'sequel'
require 'sparklines'
require 'gruff'
require 'restclient'
require 'json'
require 'pp'

module Points
	def self.data
		@@data ||= make
	end

	def self.make
		db = Sequel.connect(ENV['DATABASE_URL'] || 'sqlite://rifgraf.db')
		make_table(db)
		db[:points]
	end

	def self.make_table(db)
		db.create_table :points do
			varchar :graph, :size => 32
			varchar :value, :size => 32
			timestamp :timestamp
		end
	rescue Sequel::DatabaseError
		# assume table already exists
	end
end

helpers do
	def graphs_from_params(seperator)
		[ params[:id] ] + (params[:and] || '').split(seperator)
	end
end

get '/' do
	erb :about
end

get '/graphs/:id.html' do
	graphs_from_params(',').each do |graph|
		throw :halt, [ 404, "No such graph \"#{graph}\"" ] unless Points.data.filter(:graph => graph).count > 0
	end
	erb :graph, :locals => { :id => params[:id], :others => (params[:and] || '').gsub(/,/, '+') }
end

get '/graphs/:id/amstock_settings.xml' do
	erb :amstock_settings, :locals => { :graphs => graphs_from_params(' ') }
end

get '/graphs/:id/sparkline.png' do
  points = Points.data.filter(:graph => params[:id]).reverse_order(:timestamp).first(400)
  content_type :png
  last_modified points.first[:timestamp]
  Sparklines.plot points.map {|p| p[:value].to_f }, :type => 'smooth'
end

get '/graphs/:id.png' do
  points = Points.data.filter(:graph => params[:id]).reverse_order(:timestamp).first(400)
  content_type :png
  last_modified points.first[:timestamp]

  g = Gruff::Line.new
  g.title = params[:id]
  g.data 'Hash Rate', points.map {|p| p[:value].to_f}
  g.to_blob
end

get '/graphs/:id/data.csv' do
	erb :data, :locals => { :points => Points.data.filter(:graph => params[:id]).reverse_order(:timestamp) }
end

post '/graphs/:id' do
	Points.data << { :graph => params[:id], :timestamp => (params[:timestamp] || Time.now), :value => params[:value] }
	"ok"
end

delete '/graphs/:id' do
	Points.data.filter(:graph => params[:id]).delete
	"ok"
end

get '/pull_data' do
  stats = JSON.parse(RestClient.get('https://pool.bitp.it/api/pool'))
  Points.data << { :graph => 'bitp.it', :timestamp => Time.now, :value => stats['ghashes_ps'] }
  "ok"
end
