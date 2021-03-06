class Rules < ActiveModel::Validator

  @@max_segs = 4

  def validate(record)
    unless has_valid_format?(record)
      record.errors[:format] << 'Dates were not properly formatted'
      # we need to exit because inproperly formatted date will cause
      # other validations to throw up
      return
    end

    unless at_least_week?(record)
      record.errors[:end_at] << 'Segments must be at least 7 days long'
      return
    end

    unless up_to_max_segs?(record)
      record.errors[:segs] << 'You have more than 4 segments. Please add vacation days to an existing segment'
      return
    end

    if overlaps?(record)
      record.errors[:overlap] << 'Vacation weeks must not overlap'
      return
    end

    unless less_than_allowed?(record)
      record.errors[:allowed] << 'You have selected more vacation days than you have accrued'
      return
    end

    unless less_than_max_per_day?(record)
      record.errors[:max_day] << 'You have selected a day that has no more availability'
      return
    end
    
    unless holiday_restriction?(record)
      record.errors[:holiday] << 'There are no more availabilities for this day due to the holidays'
    end

    unless valid_pto?(record)
      record.errors[:pto] << 'You have selected more than one week of PTO'
    end
    
    unless in_year?(record)
      record.errors[:year] << 'Please select a vacation for the currently scheduled year'
    end
  end
  
  def in_year?(record)
    year = CurrentYear.first.year
    # vacation segment is from Mar of this year to Feb of next year
    if record.start_at.year == year && record.start_at.month >= 3 &&
      (record.end_at.year == year || record.end_at.year == year+1 &&
      record.end_at.month < 3)
      return true
    # vacation is from start of next year to Feb of next year
    elsif record.start_at.year == year + 1 && record.start_at.month < 3 &&
      record.end_at.year == year + 1 && record.end_at.month < 3
      return true
    else return false
    end
  end

  def valid_pto?(record)
    if record.pto == false
      return true
    end
    if calculate_length(record) != 7
      return false
    end
    record.nurse.events.each do |e|
      if e.id == record.id
        next
      end
      if e.pto == true
        return false
      end
    end
    return true
  end

  #dates should be formatted properly
  def has_valid_format?(record)
    return (is_date?(record.start_at) and is_date?(record.end_at))
  end

  def is_date?(date)
    begin
      DateTime.parse(date.to_s)
    rescue
      return false
    end
    return true
  end

  
  #should not allow users to select another segment that overlaps with another user segment
  def overlaps?(record)
    events = Event.find_all_by_nurse_id(record.nurse_id)
    events.each do |e|
      if e.id == record.id
        next
      end

      # start dates overlap
      if (e.start_at.to_date <= record.start_at.to_date) and (record.start_at.to_date <= e.end_at.to_date)
        return true
      end
      # end dates overlap
      if (e.start_at.to_date <= record.end_at.to_date) and (record.end_at.to_date <= e.end_at.to_date)
        return true
      end
      # e contains record
      if (e.start_at.to_date < record.start_at.to_date) and (record.end_at.to_date < e.end_at.to_date)
        return true
      end
      # record contains e
      if (e.start_at.to_date > record.start_at.to_date) and (record.end_at.to_date > e.end_at.to_date)
        return true
      end 
    end
    return false
  end
  
  # at least one week
  def at_least_week?(record)
    return calculate_length(record) >= 7
  end

  def up_to_max_segs?(record)
    events = Event.find_all_by_nurse_id(record.nurse_id) # the current one is #4
    if not events
      return true
    else
      return events.length <= @@max_segs-1
    end
  end

  # no more weeks than allowed
  def less_than_allowed?(record)
    num_days_total = record.nurse.num_weeks_off * 7
    num_days_taken = 0
    events = Event.find_all_by_nurse_id(record.nurse_id)
    events.each do |event|
      num_days_taken += calculate_length(event)
    end
    num_days_taken += calculate_length(record)
    return num_days_taken <= num_days_total
  end

  def less_than_max_per_day?(record)
    @shift = record.nurse.shift
    @unit_id = record.nurse.unit.id
    @max_per = record.nurse.unit.calculate_max_per_day(@unit_id, @shift)
    start_date = record.start_at.to_date
    end_date = record.end_at.to_date
    while start_date <= end_date do
      @num_on_this_day = num_nurses_on_day(start_date, @shift, @unit_id, record.id)
      if @num_on_this_day < @max_per[:year]
        start_date = start_date.next_day
      elsif less_than_max_in_additional_month?(start_date)
        start_date = start_date.next_day
      else
        return false
      end
    end
    return true
  end

  def less_than_max_in_additional_month?(start_date)
    max_this_month = 0
    curr_month = start_date.month
    @start_months = UnitAndShift.get_additional_months(@unit_id, @shift)
    @months = create_month_list(@start_months)
    @months.each do |month|
      if curr_month == month
      max_this_month += 1
      end
    end
    return @num_on_this_day < @max_per[:year] + max_this_month
  end
  
  # admins can limit how many nurses can be off during the holidays
  def holiday_restriction?(record)
    @unit = record.nurse.unit_id
    @shift = record.nurse.shift
    holiday_limit = UnitAndShift.get_holiday_obj(@unit, @shift)
    if holiday_limit != nil && during_holidays(record)# no holiday restriction
      num_today = num_nurses_on_day(record.start_at, @shift, @unit, record.id)
      return num_today < holiday_limit.holiday
    else return true
    end
  end
  
 def create_month_list(start)
    @rtn_months = []
    if start != nil
      start.each do |s|
        @rtn_months << s
        @rtn_months << (s + 1) % 12
        @rtn_months << (s + 2) % 12
      end
    end
    return @rtn_months
  end
    
  def num_nurses_on_day(start_date, shift, unit_id, id)
    max_weeks = 6 
    range_buffer = (max_weeks * 7) + 1

    events = Event.joins(:nurse)
                  .where(
                          'nurses.shift' => shift,
                          'nurses.unit_id' => unit_id
                          )
                  .where(
                          'events.start_at between ? and ?', start_date - range_buffer, start_date + 1
                          )

    num_nurses = 0 
    events.each do |e|
      if e.id == id
        next
      end
      
      if (e.start_at.to_date <= start_date) and (start_date <= e.end_at.to_date)
        num_nurses += 1
      end
    end

    return num_nurses
  end

  def calculate_length (event)
    start_at = event.start_at.to_date
    end_at = event.end_at.to_date
    return (end_at - start_at).to_i + 1
  end

  def during_holidays(record)
    @year = CurrentYear.first.year
    @holiday_start = Date.new(@year, 12, 20)
    @holiday_end =  Date.new(@year+1, 1, 2)
    if record.start_at.to_date >= @holiday_start &&
      record.start_at.to_date <= @holiday_end
      return true
    elsif record.end_at.to_date >= @holiday_start &&
      record.end_at.to_date <= @holiday_end
      return true
    elsif record.start_at.to_date <= @holiday_start && record.end_at.to_date >= @holiday_end
      return true
    else return false
    end
  end
end
