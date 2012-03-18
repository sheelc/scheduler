# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20120314222702) do

  create_table "admins", :force => true do |t|
    t.string "name"
  end

  create_table "nurses", :force => true do |t|
    t.string  "name"
    t.string  "shift"
    t.integer "unit_id"
    t.integer "seniority"
    t.integer "num_weeks_off"
  end

  create_table "nurses_vacation_days", :id => false, :force => true do |t|
    t.integer "nurse_id"
    t.integer "vacation_day_id"
  end

  create_table "units", :force => true do |t|
    t.string "name"
  end

  create_table "vacation_days", :force => true do |t|
    t.date    "date"
    t.integer "remaining_spots"
    t.string  "shift"
    t.integer "unit_id"
  end

end