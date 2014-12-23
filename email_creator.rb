require 'gmail'
require 'pry'
require 'liquid'
require 'csv'
require 'tty' 

class EmailTemplate
  attr_reader :data, :subject
  def initialize(template, data, subject, gmail)
    @template, @data, @subject, @gmail = template, data, subject, gmail
  end

  def email_to
    @data['email']
  end

  def email_data
    [email_to, subject, email_body]
  end

  def email_body
    render
  end

  def send!(to_email=nil)
    composed_email = email
    composed_email.to = to_email if to_email
    puts "sending to #{composed_email.to}...."
    composed_email.deliver!
    puts "sent!"
  end

  def email
    gmail_email = @gmail.compose
    gmail_email.to = email_to
    gmail_email.subject= subject
    gmail_email.body = email_body
    gmail_email
  end

  def render
    Liquid::Template.parse(@template).render(@data)
  end
end


class EmailGenerator
  attr_accessor :email_template, :email_variables, :subject
  attr_accessor :email_template_path, :email_csv_path
  
  def initialize(email_template_path, email_csv_path, subject, gmail)
    @email_template_path, @email_csv_path, @subject, @gmail = email_template_path, email_csv_path, subject, gmail
  end

  def email_template
    read_template(@email_template_path)
  end

  def email_variables
    read_csv(@email_csv_path)
  end

  def email_data
    puts "generating text for #{email_variables.length} emails"
    templates.map(&:email_data)
  end

  def send_preview_to_self!
    templates.first.send!(@gmail.username)
  end

  def send_all!
    templates.map(&:send!)
  end

  def templates
    email_variables.map do |email_hash|
      template(email_hash)
    end
  end

  def preview
    email_table.render :ascii, multiline: true
  end

  def email_table
    TTY::Table.new(header: ['email', 'subject', 'body'], rows: email_data)
  end

  private

  def template(email_hash)
    EmailTemplate.new(email_template, email_hash, subject, @gmail)
  end
  def read_template(email_template_path)
    File.read(email_template_path)
  end

  def read_csv(path)
    CSV.new(File.read(path), headers: true).map(&:to_hash)
  end
end

def connect_to_gmail(email, password)
  gmail = Gmail.connect(email, password)
  if gmail.logged_in?
    return gmail
  else
    false
  end
end
shell = TTY::Shell.new
email = shell.ask("Gmail Email:") do 
  modify :strip
  on_error :retry
end.read_email

password = shell.ask("Gmail password:") do 
  mask(true)
end.read_password

gmail = connect_to_gmail(email, password)
subject = shell.ask("Email Subject") do 
  modify :strip
  on_error :retry
end.read_string

input_template = shell.ask("Email Template (default is email.txt.liquid)") do
  modify :strip
end.read_string

input_csv = shell.ask("Email CSV (default is email_csv.csv") do
  default 'email_csv.csv'
  modify :strip
end.read_string

template_path = input_template.blank? ? 'email.txt.liquid' : input_template
csv_path = input_csv.blank? ? 'email_csv.csv' : input_csv
shell.confirm "logged into gmail #{gmail.username}" if gmail
shell.error "Couldn't log into gmail" unless gmail
generator = EmailGenerator.new(template_path, csv_path, subject, gmail)
puts generator.preview
if shell.ask("send preview to self?").read_bool
  generator.send_preview_to_self!
end
if shell.ask("send all emails?").read_bool && shell.ask("you sure?").read_bool
  generator.send_all!
end

