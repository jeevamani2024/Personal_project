






USE Insurance
GO
/*
-------------------------------------------------------------
------------------- Days to Publish Query -------------------
-------------------------------------------------------------
*/
SELECT
Pub.ClaimNumber
, Pub.OfficeCode
, Pub.ExaminerCodeAtTimeOfPublish
, CASE WHEN SUM(CASE WHEN NewOrUpdated_Save = 'New' THEN 1 ELSE 0 END) > 0 THEN 
'New' ELSE 'Updated' END AS NewOrUpdated_Publish
, SUM(HoursFinal) as HoursSpentToPublish
, Pub.DatePublished
FROM
(
------------------- Date Published with Examiner Query -------------------
SELECT ClaimNumber
, O.OfficeCode
, clmLg.NewValue as 'ExaminerCodeAtTimeOfPublish'
, DatePublished
, PriorDatePublished
FROM
(
--------- Get the Date Published query along with the last time the examiner 
select pk
, pub1.ClaimNumber
, pub1.DatePublished
, pub1.PriorDatePublished
, max(z.entrydate) as AssignedDate
from [ClaimLog] z
INNER JOIN [Claim] C ON C.ClaimID = z.PK
INNER JOIN 
(
/*
------------------- Date Published along with Prior Date Published
 Query
------------------- The Prior Date Published will be used to join 
onto the larger Save and Retrieve Query*/
SELECT ClaimNumber, EnteredOn as DatePublished
, LAG (EnteredOn, 1, NULL) OVER (PARTITION BY ClaimNumber 
ORDER BY EnteredOn) AS PriorDatePublished
FROM [ReservingTool]
WHERE IsPublished = 1 AND ClaimNumber IS NOT NULL
--ORDER BY ClaimNumber, EnteredOn DESC
) Pub1
ON Pub1.ClaimNumber = C.ClaimNumber AND z.entrydate < 
Pub1.DatePublished
where FieldName = 'examinercode'
group by pk
, pub1.ClaimNumber
, pub1.DatePublished
, pub1.PriorDatePublished
--order by pk
--order by ClaimNumber
) z
INNER JOIN [ClaimLog] clmLg ON clmLg.PK = z.PK and clmLg.EntryDate = z.AssignedDate and clmLg.FieldName = 'ExaminerCode'
LEFT JOIN [Users] U ON U.Username = clmLg.NewValue
LEFT JOIN [Office] O ON O.OfficeID = U.OfficeID
--order by claimnumber
) Pub
INNER JOIN
(
------------------- Query to find the final time between retrievals and saves 
-------------------
SELECT DISTINCT 
ClaimNumber
, MaxSavedDate as MaxSavedOrPublishedDate
, MinRetrievalDate
, TotalSubtractHours
, NewOrUpdated_Save
, DATEDIFF(SECOND, MinRetrievalDate, MaxSavedDate)/(60.0 * 60.0) + 
TotalSubtractHours AS HoursFinal
FROM
(
/*
------------ Here we find the Maximum Saved Date and the Minimum Retrieval
 Date. The difference will be the Gross Time Spent.
------------ We will then calculate the exact number of hours worked by 
subtracting out the down-time
------------ This query finds the down time by finding which retrieves 
were not the first retrieve on 
------------ the day (Flag_FirstRetrieveOfDay = 0), and finding if that 
retrieve came after a save 
------------ earlier in the day (PriorSave_SameDay).
------------ If it did come after a save earlier in the day, we find the 
time between the retrieve and 
------------ the prior save = the down-time.*/
SELECT *
, MAX(DateSavedOrPublished) OVER (PARTITION BY ClaimNumber, convert
(date, DateSavedOrPublished)) as MaxSavedDate
, MIN(RetrieveDate) OVER (PARTITION BY ClaimNumber, convert(date, 
DateSavedOrPublished)) as MinRetrievalDate
, SUM(CASE WHEN Flag_FirstRetrieveOfDay = 0 THEN DATEDIFF(SECOND, 
RetrieveDate, PriorSave_SameDay)/(60.0 * 60.0) ELSE 0 END) OVER 
(PARTITION BY ClaimNumber, convert(date, DateSavedOrPublished)) AS 
TotalSubtractHours
, CASE WHEN SUM(NewFlag) OVER (PARTITION BY ClaimNumber, convert(date,
DateSavedOrPublished)) > 0 THEN 'New' ELSE 'Updated' END as 
NewOrUpdated_Save
FROM 
(
SELECT Sav.ClaimNumber
, Sav.IsPublished
, Sav.DateSavedOrPublished
, Sav.PriorDateSavedOrPublished
, CASE WHEN Sav.PriorDateSavedOrPublished IS NULL THEN NULL
WHEN convert(date, Sav.DateSavedOrPublished) = convert
(date, Sav.PriorDateSavedOrPublished) THEN 
Sav.PriorDateSavedOrPublished
ELSE NULL 
END as PriorSave_SameDay
, Ret.RetrieveDate
, Ret.PriorRetrieveDate
, CONVERT(DATETIME, MAX(Flag_LastSaveOfTheDay * convert(float, 
DateSavedOrPublished)) OVER (PARTITION BY Sav.ClaimNumber, 
convert(date, Sav.DateSavedOrPublished))) as 
RemoveSavesAfterThisTimeInDay
, Flag_FirstRetrieveOfDay
, ROW_NUMBER() OVER (PARTITION BY Sav.ClaimNumber, 
Sav.DateSavedOrPublished ORDER BY Ret.RetrieveDate) as 
RetrieveOrder
, CASE WHEN Sav.PriorDateSavedOrPublished IS NULL THEN 1 ELSE 0 
END AS NewFlag
FROM
(/*
------------------- Find all the Save/Publish dates, the 
------------------- prior saves/publishes on their claim, 
and
------------------- flag if it is the last save/publish*/
SELECT ClaimNumber
, IsPublished
, EnteredOn as DateSavedOrPublished
, LAG (EnteredOn, 1, NULL) OVER (PARTITION BY ClaimNumber 
ORDER BY EnteredOn) AS PriorDateSavedOrPublished
, CASE WHEN SUM(ispublished + 0) OVER (PARTITION BY 
ClaimNumber, convert(date, enteredon)) > 0 
THEN CASE WHEN CONVERT(float, enteredon) = MAX
(CONVERT(float, enteredon) * IsPublished) OVER (PARTITION BY 
ClaimNumber, convert(date, enteredon)) THEN 1 ELSE 0 END 
ELSE CASE WHEN enteredon = MAX(EnteredOn) OVER 
(PARTITION BY ClaimNumber, convert(date, enteredon)) THEN 1 ELSE
0 END
END AS Flag_LastSaveOfTheDay
FROM [ReservingTool]
WHERE IsSaved = 1 AND ClaimNumber IS NOT NULL
--ORDER BY ClaimNumber, EnteredOn DESC
) Sav
LEFT JOIN
(
------------------- Find all the Retrieve dates, the 
------------------- prior retrieves on their claim, and
------------------- flag if it is the first retrieve
SELECT ClaimNumber, EnteredOn as RetrieveDate
, LAG (EnteredOn, 1, NULL) OVER (PARTITION BY ClaimNumber 
ORDER BY EnteredOn) AS PriorRetrieveDate
, CASE WHEN enteredon = MIN(EnteredOn) OVER (PARTITION BY 
ClaimNumber, convert(date, enteredon)) THEN 1 ELSE 0 END AS 
Flag_FirstRetrieveOfDay
FROM [ReservingTool]
WHERE IsPublished = 0 AND IsSaved = 0 AND ClaimNumber IS NOT 
NULL
--ORDER BY ClaimNumber, EnteredOn DESC
) Ret
ON Sav.ClaimNumber = Ret.ClaimNumber 
AND (CONVERT(date, Sav.DateSavedOrPublished) = TRY_CONVERT(date, 
Ret.RetrieveDate) OR Ret.RetrieveDate IS NULL)
AND Ret.RetrieveDate <= Sav.DateSavedOrPublished
AND (Ret.RetrieveDate > Sav.PriorDateSavedOrPublished OR 
Sav.PriorDateSavedOrPublished IS NULL)
WHERE (Ret.RetrieveDate IS NULL 
OR CONVERT(date, Sav.DateSavedOrPublished) = TRY_CONVERT(date,
Ret.RetrieveDate))
) x
WHERE RetrieveOrder = 1 AND DateSavedOrPublished <= 
RemoveSavesAfterThisTimeInDay
) y
WHERE MinRetrievalDate IS NOT NULL
--ORDER BY ClaimNumber, MaxSavedDate
) SavRet
ON Pub.ClaimNumber = SavRet.ClaimNumber 
AND SavRet.MaxSavedOrPublishedDate <= Pub.DatePublished
AND (SavRet.MaxSavedOrPublishedDate > Pub.PriorDatePublished OR 
Pub.PriorDatePublished IS NULL)
GROUP BY Pub.ClaimNumber
, Pub.OfficeCode
, Pub.ExaminerCodeAtTimeOfPublish
, Pub.DatePublished
ORDER BY Pub.ClaimNumber, DatePublished