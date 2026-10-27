/* =====================================================================
   Script:    Patient_No_show_analysis.sql
   Project:   Healthcare Analysis (Medical Appointment No-Shows)
   Dataset:   KaggleV2-May-2016.csv (110,527 rows, 14 columns)
   Database:  healthcare_analysis (MySQL 9.7.1, MySQL Workbench on macOS)

   Purpose:   Create the `appointments` table and load the raw CSV
              into it, keeping accented characters (e.g. REPÚBLICA,
              SÃO PEDRO) intact.


   WHY LOAD DATA INSTEAD OF THE IMPORT WIZARD:
   Workbench's Table Data Import wizard failed on my Mac with:
     "'ascii' codec can't decode byte 0xc3 in position 725"
   The wizard runs on Python, which defaulted to ASCII on my machine
   and could not read the accented characters in the Neighbourhood
   column. Setting the wizard's Encoding to utf-8 did not help. Using
   LOAD DATA with CHARACTER SET utf8mb4 avoids the wizard and keeps
   the CSV untouched.
   ===================================================================== */


/* ---------------------------------------------------------------------
   ONE-TIME SETUP: allow local file loading
   Loading a local file needs the setting enabled on BOTH sides.
   Without both, MySQL gives Error 3948 or Error 2068.
   --------------------------------------------------------------------- */

-- (1) SERVER SIDE: run this in a query tab.
--     Resets if the MySQL server restarts, so re-run if error 3948 returns.
SET GLOBAL local_infile = 1;

-- (2) CLIENT SIDE (not SQL, done in the Workbench interface):
--     Database > Manage Connections > select the connection >
--     Advanced tab > in the "Others" box, add a NEW LINE:
--         OPT_LOCAL_INFILE=1
--     Click Close to save, then fully quit and reopen Workbench
--     (Cmd+Q) so the setting applies to the new connection.
--     Must be done separately for each connection used.


/* ---------------------------------------------------------------------
   STEP 1: Select the database
   --------------------------------------------------------------------- */
USE healthcare_analysis;


/* ---------------------------------------------------------------------
   STEP 2: Create the table

   Column notes:
   - PatientId is VARCHAR because it is an identifier, not a number
     to calculate with, and the values are up to 15 digits long.
   - Column names `Hipertension` and `Handcap` keep the original
     spellings from the dataset, so they match the source file.
   - `No-show` needs backticks because of the hyphen.
     'Yes' = patient missed the appointment, 'No' = patient attended.
   - utf8mb4 is used so accented characters are stored correctly.
   --------------------------------------------------------------------- */

CREATE TABLE appointments (
  PatientId       VARCHAR(20),
  AppointmentID   INT,
  Gender          VARCHAR(5),
  ScheduledDay    DATETIME,      -- when the appointment was booked
  AppointmentDay  DATETIME,      -- day of the appointment (time is 00:00)
  Age             INT,
  Neighbourhood   VARCHAR(100),
  Scholarship     TINYINT,       -- 1 = enrolled in welfare program
  Hipertension    TINYINT,       -- 1 = has hypertension
  Diabetes        TINYINT,
  Alcoholism      TINYINT,
  Handcap         TINYINT,
  SMS_received    TINYINT,       -- 1 = reminder SMS was sent
  `No-show`       VARCHAR(5)     -- 'Yes' / 'No'
) CHARACTER SET utf8mb4;


/* ---------------------------------------------------------------------
   STEP 3: Load the CSV
   - CHARACTER SET utf8mb4 : reads the file as UTF-8 (keeps accents).
   - IGNORE 1 LINES        : skips the header row.
   - @sched / @appt        : dates are read into variables first because
                             the CSV format (2016-04-29T18:38:08Z)
                             isn't MySQL's DATETIME format. STR_TO_DATE
                             converts them. The trailing 'Z' (UTC) is
                             matched as text, so no timezone shift is
                             applied.
   --------------------------------------------------------------------- */
LOAD DATA LOCAL INFILE '/path/to/KaggleV2-May-2016.csv'
INTO TABLE medical_appointments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
IGNORE 1 LINES
(PatientId, AppointmentID, Gender, @sched, @appt, Age, Neighbourhood,
 Scholarship, Hipertension, Diabetes, Alcoholism, Handcap, SMS_received, `No-show`)
SET ScheduledDay   = STR_TO_DATE(@sched, '%Y-%m-%dT%H:%i:%sZ'),
    AppointmentDay = STR_TO_DATE(@appt,  '%Y-%m-%dT%H:%i:%sZ');


/* ---------------------------------------------------------------------
   STEP 4: DATA QUALITY CHECK
   
   Expected: 110527 rows, no NULL dates, 'No-show' has only Yes / No,
   and accented neighbourhood names display correctly.
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS total_rows FROM medical_appointments;

SELECT COUNT(*) AS null_dates
FROM medical_appointments
WHERE ScheduledDay IS NULL OR AppointmentDay IS NULL;

SELECT DISTINCT `No-show` FROM medical_appointments;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT AppointmentID) AS unique_appointments,
    SUM(Age < 0) AS negative_age_records,
    SUM(lead_time_days < 0) AS negative_lead_time_records,
    SUM(ScheduledDay IS NULL) AS null_scheduled_dates,
    SUM(AppointmentDay IS NULL) AS null_appointment_dates
FROM medical_appointments;

SELECT * FROM medical_appointments
LIMIT 10;

DESCRIBE medical_appointments;

/* -----------------------------------------------------------------*/

-- Data Cleaning

ALTER TABLE medical_appointments
	CHANGE COLUMN Hipertension Hypertension INT,
	CHANGE COLUMN Handcap disablity_count INT, 
	CHANGE COLUMN `No-show` no_show VARCHAR(5);

/* -----------------------------------------------------------------------
Handcap should not automatically be interpreted as a simple yes/no field.
Its numeric values represents no. of disablities a person has. 
------------------------------------------------------------------------- */ 

-- Modified AppointmentDay from Datetime to Date
ALTER TABLE medical_appointments
	MODIFY COLUMN AppointmentDay DATE;

SELECT * 
FROM medical_appointments
LIMIT 10;

SELECT
	MIN(age),
	MAX(age)
FROM medical_appointments;
-- min(age) is coming -1 and negative age isn't valid

SELECT age
FROM medical_appointments
WHERE age < 0;
-- there is only one record of negative age i.e age of -1, we remove it then 

-- Turn off safe-update mode for this session so UPDATE/DELETE without a key-column WHERE clause (Error 1175) 
-- is allowed during cleaning. Re-enable with SET SQL_SAFE_UPDATES = 1; when done.
SET SQL_SAFE_UPDATES = 0;  

DELETE FROM medical_appointments
WHERE age = -1;

-- Lead-time: the number of days between when someone booked the appointment and when the appointment actually happened
ALTER TABLE medical_appointments
ADD COLUMN lead_time_days INT;

UPDATE medical_appointments
SET lead_time_days = DATEDIFF(AppointmentDay, DATE(ScheduledDay));

SELECT 
	MIN(lead_time_days),
    MAX(lead_time_days)
FROM medical_appointments;

SELECT * 
FROM medical_appointments
WHERE lead_time_days < 0;

DELETE FROM medical_appointments
WHERE lead_time_days < 0;

SET SQL_SAFE_UPDATES = 1;
-- Data Quality Check: Identified 5 records with negative lead times out of 110,527 records (0.0045%). 
-- These records will be excluded from the analysis due to their negligible proportion. 

SELECT * FROM medical_appointments LIMIT 10;

-- Exploratory data analysis

-- 1. What's the overall no-show rate ?
WITH total_appointments AS(
	SELECT 
		COUNT(*) AS total_appointments
	FROM medical_appointments
)
SELECT 
	no_show,
    COUNT(*) AS appear_count,
	ROUND(COUNT(*) * 100/total_appointments, 2) AS no_show_rate
FROM medical_appointments
CROSS JOIN total_appointments
GROUP BY 
	no_show,
    total_appointments;

-- 2. Does the day of week matter
SELECT 
	DAYNAME(AppointmentDay) AS day_of_week,
	COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate
FROM medical_appointments
GROUP BY day_of_week
ORDER BY no_show_rate DESC; 

-- 3. Does Lead time matter 

-- same day
-- 1-3 days 
-- within a week (4-7 days)
-- long lead (8+ days)
    
SELECT 
	CASE
		WHEN lead_time_days = 0 THEN "Same day"
        WHEN lead_time_days BETWEEN 1 AND 3 THEN "1-3 Days"
        WHEN lead_time_days BETWEEN 4 AND 7 THEN "Within a week (4-7 days)"
        WHEN lead_time_days >= 8 THEN "Long lead (8+ days)"
	END AS lead_time_segments,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate
FROM medical_appointments 
GROUP BY lead_time_segments
ORDER BY no_show_rate DESC;

-- 4. Age groups

-- child (0 - 12)
-- teen (13 - 19)
-- young adult (20 - 39)
-- adult (40 - 59)

SELECT 
	CASE 
		WHEN age BETWEEN 0 AND 12 THEN 'Child'
        WHEN age BETWEEN 13 AND 19 THEN 'Teen'
        WHEN age BETWEEN 20 AND 39 THEN 'Young Adults'
        WHEN age BETWEEN 40 AND 59 THEN 'Adults'
        ELSE 'Seniors'
	END AS age_groups,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate
FROM medical_appointments
GROUP BY age_groups
ORDER BY no_show_rate DESC;

-- 5. Does SMS reminders help

SELECT 
	CASE 
		WHEN SMS_received = 1 THEN 'SMS received'
        ELSE 'No SMS received'
	END reminder_status,
    COUNT(*) AS total_appointments,
	SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate
FROM medical_appointments
GROUP BY reminder_status
ORDER BY no_show_rate DESC;

-- Is the higher no-show rate among appointments with SMS reminders 
-- explained by those appointments having longer lead times?

SELECT 
	CASE
		WHEN lead_time_days = 0 THEN "Same day"
        WHEN lead_time_days BETWEEN 1 AND 3 THEN "1-3 Days"
        WHEN lead_time_days BETWEEN 4 AND 7 THEN "Within a week (4-7 days)"
        WHEN lead_time_days >= 8 THEN "Long lead (8+ days)"
	END AS lead_time_segments,
    CASE 
		WHEN SMS_received = 1 THEN 'SMS received'
        ELSE 'No SMS received'
	END reminder_status,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate
FROM medical_appointments 
GROUP BY 
	lead_time_segments,
    reminder_status
ORDER BY no_show_rate DESC; 

/* ---------------------------------------------------------------------------------------------------------------------------------
Hypothesis: SMS reminders are more common for appointments with longer lead times, which have higher no-show rates. 
This may explain why the overall no-show rate is higher among SMS-received appointments.

Conclusion: Within each comparable lead-time segment, appointments with SMS received have lower no-show rates than those without SMS.
This suggests SMS reminders may help reduce no-shows, although the observational data does not establish causation.
--------------------------------------------------------------------------------------------------------------------------------- */

-- 6. Which Neighbourhood have the highest risk? 
SELECT 
	Neighbourhood,
    COUNT(*) AS total_appointments,
    SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) AS no_show_count,
    ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) AS no_show_rate,
    DENSE_RANK() OVER(ORDER BY ROUND(SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) * 100/ COUNT(*), 2) DESC) AS risk_rank
FROM medical_appointments 
GROUP BY Neighbourhood
HAVING COUNT(*) >= 100
ORDER BY no_show_rate DESC
LIMIT 15;

-- 7. Patient-level risk scoring
SELECT
	PatientId,
    AppointmentID,
    AppointmentDay,
    no_show,
    COUNT(*) OVER(
		PARTITION BY PatientId
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_appointments,
	SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) OVER(
		PARTITION BY PatientId
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_no_shows
FROM medical_appointments
ORDER BY PatientId ASC, AppointmentDay ASC;


-- 8. Apointment risk-based classification
CREATE VIEW v_appoitment_risk AS
WITH patient_history AS(
	SELECT 
		PatientId,
        AppointmentID,
        AppointmentDay,
        Neighbourhood,
        lead_time_days,
        SMS_received,
        Scholarship,
        no_show,
        COUNT(*) OVER(
		PARTITION BY PatientId
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_appointments,
	SUM(CASE WHEN no_show = 'Yes' THEN 1 ELSE 0 END) OVER(
		PARTITION BY PatientId
        ORDER BY AppointmentDay
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_no_shows
	FROM medical_appointments
)
SELECT 
	PatientId,
	AppointmentID,
	AppointmentDay,
	Neighbourhood,
    lead_time_days,
    prior_appointments,
    prior_no_shows,
	ROUND(prior_no_shows/ NULLIF(prior_appointments, 0), 2) AS prior_no_show_rate,
	CASE 
		WHEN prior_appointments = 0 THEN 'New Patient - Monitor'
        WHEN (prior_no_shows/ NULLIF(prior_appointments, 0)) >= 0.5 
			OR lead_time_days >= 8 THEN 'High Risk'
		WHEN (prior_no_shows/ NULLIF(prior_appointments, 0)) >= 0.2 
			OR lead_time_days BETWEEN 4 AND 7 THEN 'Medium Risk'
		ELSE 'Low Risk'
	END AS risk_tier
FROM patient_history;

/*
Purpose: Create a reusable view to classify appointment risk using each patient's
previous appointment history and the current appointment's lead time.

The view calculates the number of prior appointments, prior no-shows, and the
historical no-show rate for each patient, excluding the current appointment
from the historical calculations to avoid using its outcome.

Risk tiers are assigned using predefined, rule-based thresholds for historical
no-show rates and lead times. These thresholds are assumptions for this project,
not industry-standard criteria or a validated predictive model.

The goal is to identify appointments that may be at higher risk of a no-show
and support further analysis of appointment attendance patterns.
*/
