#!/usr/bin/env osascript

on run
  try
    set currentDate to current date

    tell application "Calendar"
      -- Check for events starting in the next 10 minutes
      set upcomingEvents to (every event of calendar "Work" whose¬
        ((start date > currentDate and start date <= (currentDate + (20 * minutes)))¬
          or end date <= (currentDate + (10 * minutes))¬
        and allday event is false))

      -- Check for events ending in the next 10 minutes
      -- set endingEvents to (every event of calendar "Bloomteq" whose¬
      --   (end date > currentDate and end date <= (currentDate + (15 * minutes))¬
      --   and allday event is false))

      if (count of upcomingEvents) > 0 then
        return true
      -- else if (count of endingEvents) > 0 then
      --   return false
      else
        return false
      end if

    end tell

  on error
    return false

  end try
end run
