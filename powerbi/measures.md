# DAX Measures

This file documents the DAX measures used in the Power BI dashboard (`Patient No-show Analysis.pbix`). All measures live in a dedicated measures table.

## Summary

| Measure | What it calculates |
|---|---|
| **Total Appointments** | Counts unique appointment IDs in the patient risk table. This is the base for the other measures. |
| **No-show appointments** | Counts unique appointment IDs where the outcome is "Yes" (the patient missed the appointment). |
| **Overall No-show rate** | Missed appointments divided by total appointments. It responds to every slicer and visual filter, so the same measure gives the rate by weekday, lead-time group or neighbourhood. |
| **Average Lead time** | Average number of days between booking and the appointment date. |
| **risk-tier % of total** | Each risk tier's appointment count as a share of all appointments, ignoring the risk-tier filter so the percentages add up to 100%. |
| **Day of Week Color** | Returns a colour code for conditional formatting: dark blue for the weekday with the highest no-show rate, light blue for the rest. |
| **Lead Time Color** | Same highlighting logic as above, applied to the lead-time groups. |

## Formulas

### Total Appointments

```dax
Total Appointments =
DISTINCTCOUNT(
    'Patient-appointment-risk'[AppointmentID]
)
```

### No-show appointments

```dax
No-show appointments =
CALCULATE(
    DISTINCTCOUNT(
        'Patient-appointment-risk'[AppointmentID]
    ),
    medical_appointments_cleaned[no_show] = "Yes"
)
```

### Overall No-show rate

```dax
Overall No-show rate =
VAR no_show_count =
    COUNTROWS(
        FILTER(
            medical_appointments_cleaned,
            medical_appointments_cleaned[no_show] = "Yes"
        )
    )
VAR Output =
    DIVIDE(
        no_show_count,
        [Total Appointments]
    )
RETURN
    Output
```

### Average Lead time

```dax
Average Lead time =
AVERAGE(
    medical_appointments_cleaned[lead_time_days]
)
```

### risk-tier % of total

```dax
risk-tier % of total =
DIVIDE(
    [Total Appointments],
    CALCULATE(
        [Total Appointments],
        ALL(
            'Patient-appointment-risk'[risk_tier]
        )
    )
)
```

### Day of Week Color

```dax
Day of Week Color =
VAR CurrentRate = [Overall No-show rate]
VAR HighestRate =
    MAXX(
        ALLSELECTED( medical_appointments_cleaned[Day of Week] ),
        [Overall no-show rate]
    )
RETURN
    IF( CurrentRate = HighestRate, "#03045E", "#CAF0F8" )
```

### Lead Time Color

```dax
Lead Time Color =
VAR CurrentRate = [Overall no-show rate]
VAR HighestRate =
    MAXX(
        ALLSELECTED( medical_appointments_cleaned[lead_time_segments] ),
        [Overall no-show rate]
    )
RETURN
    IF( CurrentRate = HighestRate, "#03045E", "#CAF0F8" )
```
