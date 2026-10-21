/* =====================================================================
   ALTERNATIVE METHOD: convert text dates to DATETIME / DATE afterwards
   (Method taught by my instructor)

   WHEN TO USE THIS:
   If the table was created with ScheduledDay and AppointmentDay as TEXT
   (for example, when the Table Data Import wizard is used), the dates
   look like '2016-04-29T18:38:08Z' and cannot be used for date
   calculations. This section converts them after the load, so the same
   problem can be fixed in the future without reloading the file.
   NOT NEEDED for the LOAD DATA script above, which converts the dates
   while loading.

   WHY THE TWO COLUMNS GET DIFFERENT TYPES:
   - ScheduledDay    -> DATETIME: an appointment can be booked at any
                        time of day, so the time part matters.
   - AppointmentDay  -> DATE: the time is always 00:00:00, so only the
                        date carries information.

   Method: add clean columns > fill them > drop the originals > rename.
   ===================================================================== 

-- Workbench's safe-update mode blocks an UPDATE without a WHERE clause
-- (Error 1175). Turn it off for this session before running Step B.
SET SQL_SAFE_UPDATES = 0;

-- STEP A: add two new, correctly typed columns
ALTER TABLE medical_appointments
  ADD COLUMN ScheduledDayClean   DATETIME,
  ADD COLUMN AppointmentDayClean DATE;

-- STEP B: fill them from the text columns
-- REPLACE(..., 'T', ' ') swaps the 'T' separator for a space
-- REPLACE(..., 'Z', '')  removes the trailing 'Z' (UTC marker)
-- The text is then '2016-04-29 18:38:08', which STR_TO_DATE can read
-- with the format '%Y-%m-%d %H:%i:%s'.

UPDATE medical_appointments
SET ScheduledDayClean = STR_TO_DATE(
        REPLACE(REPLACE(ScheduledDay, 'T', ' '), 'Z', ''),
        '%Y-%m-%d %H:%i:%s'),
    AppointmentDayClean = DATE(STR_TO_DATE(
        REPLACE(REPLACE(AppointmentDay, 'T', ' '), 'Z', ''),
        '%Y-%m-%d %H:%i:%s'));

-- STEP C: check the conversion BEFORE dropping anything
-- Expected: 0 rows with NULL where the original text was not NULL.

SELECT COUNT(*) AS failed_conversions
FROM medical_appointments
WHERE ScheduledDayClean IS NULL OR AppointmentDayClean IS NULL;

-- STEP D: drop the original text columns
ALTER TABLE medical_appointments
  DROP COLUMN ScheduledDay,
  DROP COLUMN AppointmentDay;

-- STEP E: rename the clean columns to the original names
-- (CHANGE COLUMN needs the data type repeated)
ALTER TABLE medical_appointments
  CHANGE COLUMN ScheduledDayClean   ScheduledDay   DATETIME,
  CHANGE COLUMN AppointmentDayClean AppointmentDay DATE;

-- Optional: turn safe-update mode back on
SET SQL_SAFE_UPDATES = 1;

/* Credit: this method was taught by my instructor. I documented it
   here with help from Claude (Anthropic's AI assistant). */
