require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"

configure do
  # enable :sessions
  # set :session_secret, 'secret'
  set :erb, :escape_html => true
end

class Stock
  attr_reader :quantity, :price

  def initialize(qty:, price:)
    @quantity = qty
    @price = price
  end

  def gross_price
    quantity * price
  end

  def comission
    gross_price * 0.0025
  end

  def vat
    comission * 0.12
  end

  def pse_fee
    gross_price * 0.00005
  end

  def sccp
    gross_price * 0.0001
  end

  def sales_tax
    gross_price * 0.006
  end

  def net_buy_fee
    comission + vat + pse_fee + sccp
  end

  def net_sell_fee
    net_buy_fee + sales_tax
  end

  def net_buy_price
    gross_price + net_buy_fee
  end

  def net_sell_price
    gross_price - net_sell_fee
  end

  def percent_gain(bought_stock)
    (net_sell_price / bought_stock.net_buy_price - 1) * 100
  end

  def net_profit(bought_stock)
    net_sell_price - bought_stock.net_buy_price
  end

  def calculate_sell_price_from_percent_gain(percent_gain)
    net_sell_price = (percent_gain / 100 + 1) * net_buy_price 
    gross_sell_price = net_sell_price / 0.99105
    sell_price = gross_sell_price / quantity
  end

  def calculate_sell_price_from_net_profit(net_profit)
    net_sell_price = net_profit + net_buy_price
    gross_sell_price = net_sell_price / 0.99105
    sell_price = gross_sell_price / quantity
  end
end

def negative?(num)
  num < 0
end

def number_delimeter(num)
  num = num.round(2)
  whole, decimal = num.to_s.split(".")
  whole.delete!("-") if num.negative?
  return num if whole.size <= 3
  whole = whole.reverse.chars.each_slice(3).map(&:join).join(",").reverse
  whole = whole + "." + decimal unless decimal.nil?
  "-" + whole if num.negative?
  whole
end

get "/" do
  redirect "/home"
end

get "/home" do
  erb :home, layout: :layout
end

post "/home" do
  @results = true
  stock_quantity = params["qty"].to_f
  @bought_stock = Stock.new(qty: stock_quantity, price: params["price"].to_f)
  if params["sell-condition"] == "price"
    @sold_stock = Stock.new(qty: stock_quantity, price: params["sell-condition-amount"].to_f)
  elsif params["sell-condition"] == "percent-gain"
    sell_price = @bought_stock.calculate_sell_price_from_percent_gain(params["sell-condition-amount"].to_f)
    @sold_stock = Stock.new(qty: stock_quantity, price: sell_price) 
  elsif params["sell-condition"] == "net-profit"
    sell_price = @bought_stock.calculate_sell_price_from_net_profit(params["sell-condition-amount"].to_f)
    @sold_stock = Stock.new(qty: stock_quantity, price: sell_price) 
  end
  @quantity = 0
  @price = 0
  @amount = 0
  @quantity = number_delimeter(@bought_stock.quantity) unless @bought_stock.nil?
  @price = number_delimeter(@bought_stock.price) unless @bought_stock.nil?
  @amount = number_delimeter(params["sell-condition-amount"].to_f)
  @net_buy_price = number_delimeter(@bought_stock.net_buy_price)
  @buy_gross_price = number_delimeter(@bought_stock.gross_price)
  @net_buy_fee = number_delimeter(@bought_stock.net_buy_fee)

  @percent_gain = number_delimeter(@sold_stock.percent_gain(@bought_stock))
  @net_profit = number_delimeter(@sold_stock.net_profit(@bought_stock))
  @net_sell_price = number_delimeter(@sold_stock.net_sell_price)
  @sell_gross_price = number_delimeter(@sold_stock.gross_price)
  @net_sell_fee = number_delimeter(@sold_stock.net_sell_fee)
  @sell_price = number_delimeter(@sold_stock.price)
  erb :home, layout: :layout
end