USE Insurance
GO

/* ---- Part 1 - Create a temporary table for first query ---- */

IF OBJECT_ID('tempdb..#Temp_Timeliness') IS NOT NULL
/*Then it exists*/
DROP TABLE #Temp_Timeliness
CREATE TABLE #Temp_Timeliness (
ReservingToolID INT PRIMARY KEY
, ClaimNumber VARCHAR(50) NOT NULL
, ClaimantID INT NOT NULL
, ExaminerCode VARCHAR(50)
, SupervisorCode VARCHAR(50)
, ManagerCode VARCHAR(50)
, ExaminerTitle VARCHAR(50)
, SupervisorTitle VARCHAR(50)
, ManagerTitle VARCHAR(50)
, Office VARCHAR(50)
, PublishedDate DATETIME
, PublishOrder INT
, HandledFromStartFlag BIT
, DaysSinceLastPublish INT
, DaysToFirstPublish INT
, PublishYear INT
, PublishMonth INT
)
/* ------------------------------------------------------------- */
/* ---- Part 2 - Insert the first query into the temp table ---- */
/* ------------------------------------------------------------- */
INSERT INTO #Temp_Timeliness
SELECT ReservingToolID, ClaimNumber, ClaimantID
, ExaminerCode, SupervisorCode, ManagerCode
, ExaminerTitle, SupervisorTitle, ManagerTitle
, Office
, PublishedDate
, PublishOrder
, HandledFromStartFlag
, DaysSinceLastPublish
, DaysToFirstPublish
, PublishYear
, PublishMonth
FROM (
SELECT sub2.*
, DATEDIFF(day, PreviousPublishedDate, PublishedDate) as DaysSinceLastPublish
, CASE WHEN PublishOrder = 1 THEN DATEDIFF(day, AssignedDate, PublishedDate) 
END AS DaysToFirstPublish
, YEAR(PublishedDate) as PublishYear
, MONTH(PublishedDate) as PublishMonth
FROM (
--------- add reserves to the list of claims by reserve type and process date
SELECT sub.ClaimNumber, sub.ClaimantID, sub.ReservingToolID
, sub.ExaminerCode, sub.SupervisorCode, sub.ManagerCode
, sub.ExaminerTitle, sub.SupervisorTitle, sub.ManagerTitle
, sub.Office, sub.AssignedDate, sub.PublishedDate
, row_Number() OVER (partition by ClaimantID order by PublishedDate asc) 
as PublishOrder
, CASE WHEN try_convert(date, AssignedDate) <= try_convert(date, 
initialprocessdate) THEN 1 ELSE 0 END AS HandledFromStartFlag
, LAG(PublishedDate,1) OVER (PARTITION BY ClaimNumber ORDER BY 
PublishedDate) as PreviousPublishedDate
FROM
(
--------- get dates, resolution type, and the last CP on each claim
SELECT C.ClaimNumber, cl.ClaimantID, RT.ReservingToolID
, x.newvalue as ExaminerCode, U2.Username as SupervisorCode, 
U3.Username as ManagerCode
, U.Title as ExaminerTitle, U2.Title as SupervisorTitle, U3.Title as 
ManagerTitle
, o.OfficeDesc as Office
, y.AssignedDate
, RT.EnteredOn as PublishedDate
, cl.ClosedDate
, cl.ClaimStatusID
, min(r.processeddate) as InitialProcessDate
FROM
(
--------- get list of claims with the last time the examiner changed
select pk, max(entrydate) as AssignedDate
from [ClaimLog]
where FieldName = 'examinercode'
group by pk
--order by a.pk
) y
INNER JOIN [ClaimLog] x ON x.PK = y.PK and x.EntryDate = y.AssignedDate 
and x.FieldName = 'examinercode'
INNER JOIN [Claim] C ON C.ClaimID = y.PK
INNER JOIN [Claimant] Cl ON Cl.ClaimID = C.ClaimID
INNER JOIN [ReservingTool] RT ON C.ClaimNumber = RT.ClaimNumber and 
RT.IsPublished = 1
LEFT JOIN [Reserve] R ON Cl.ClaimantID = R.ClaimantID
LEFT JOIN [Users] U ON x.newvalue = U.Username
LEFT JOIN [Users] U2 ON U.Supervisor = U2.Username
LEFT JOIN [Users] U3 ON U2.Supervisor = U3.Username
LEFT JOIN [Office] O ON U.OfficeID = O.OfficeID
WHERE 
((cl.closeddate is null) 
OR (cl.ReopenedDate > cl.ClosedDate and cl.reopenedreasonid <> 3)
)
and r.EnteredBy not like 'DBA'
GROUP BY C.ClaimNumber, cl.ClaimantID
, RT.ReservingToolID, y.AssignedDate
, x.newvalue, U2.Username, U3.Username
, U.Title, U2.Title, U3.Title
, o.officedesc
, cl.ClosedDate
, RT.EnteredOn
, cl.ClaimStatusID
) sub
WHERE 
PublishedDate >= AssignedDate
) sub2
) sub3
WHERE DaysSinceLastPublish IS NULL OR DaysSinceLastPublish > 0

/* ---- Part 3 - Use the temp table in a query that groups and aggregates the data for
 the final results ---- */

SELECT PublishOrder
, HandledFromStartFlag
, PublishYear
, PublishMonth
, Tier1
, Tier2
, Tier3
, Tier4
, Tier5
FROM (
SELECT ReservingToolID
, CASE WHEN PublishOrder = 1 THEN 'First' ELSE 'Subsequent' END AS 
PublishOrder
, CASE WHEN PublishOrder = 1 THEN 
CASE WHEN HandledFromStartFlag = 1 THEN 'HandledFromStart' 
ELSE 'Transferred' END 
ELSE 
'N/A'
END AS HandledFromStartFlag
, PublishYear
, PublishMonth
, CASE WHEN PublishOrder = 1 THEN
CASE WHEN HandledFromStartFlag = 1 THEN
CASE WHEN DaysToFirstPublish IS NULL THEN NULL
WHEN DaysToFirstPublish <= 10 THEN 'Tier1'
WHEN DaysToFirstPublish <= 14 THEN 'Tier2'
WHEN DaysToFirstPublish <= 20 THEN 'Tier3'
WHEN DaysToFirstPublish <= 30 THEN 'Tier4'
WHEN DaysToFirstPublish >= 31 THEN 'Tier5'
ELSE 'Other' END 
ELSE
CASE WHEN DaysToFirstPublish IS NULL THEN NULL
WHEN DaysToFirstPublish <= 14 THEN 'Tier1'
WHEN DaysToFirstPublish <= 45 THEN 'Tier2'
WHEN DaysToFirstPublish <= 90 THEN 'Tier3'
WHEN DaysToFirstPublish <= 120 THEN 'Tier4'
WHEN DaysToFirstPublish >= 121 THEN 'Tier5'
ELSE 'Other' END 
END 
ELSE
CASE WHEN DaysSinceLastPublish IS NULL THEN NULL
WHEN DaysSinceLastPublish <= 30 THEN 'Tier1'
WHEN DaysSinceLastPublish <= 60 THEN 'Tier2'
WHEN DaysSinceLastPublish <= 90 THEN 'Tier3'
WHEN DaysSinceLastPublish <= 180 THEN 'Tier4'
WHEN DaysSinceLastPublish >= 181 THEN 'Tier5'
ELSE 'Other' END
END AS DayTiers
FROM #Temp_Timeliness TT
GROUP BY ReservingToolID
, CASE WHEN PublishOrder = 1 THEN 'First' ELSE 'Subsequent' END
, CASE WHEN PublishOrder = 1 THEN 
CASE WHEN HandledFromStartFlag = 1 THEN 'HandledFromStart' 
ELSE 'Transferred' END 
ELSE 
'N/A'
END
, PublishYear
, PublishMonth
, CASE WHEN PublishOrder = 1 THEN
CASE WHEN HandledFromStartFlag = 1 THEN
CASE WHEN DaysToFirstPublish IS NULL THEN NULL
WHEN DaysToFirstPublish <= 10 THEN 'Tier1'
WHEN DaysToFirstPublish <= 14 THEN 'Tier2'
WHEN DaysToFirstPublish <= 20 THEN 'Tier3'
WHEN DaysToFirstPublish <= 30 THEN 'Tier4'
WHEN DaysToFirstPublish >= 31 THEN 'Tier5'
ELSE 'Other' END 
ELSE
CASE WHEN DaysToFirstPublish IS NULL THEN NULL
WHEN DaysToFirstPublish <= 14 THEN 'Tier1'
WHEN DaysToFirstPublish <= 45 THEN 'Tier2'
WHEN DaysToFirstPublish <= 90 THEN 'Tier3'
WHEN DaysToFirstPublish <= 120 THEN 'Tier4'
WHEN DaysToFirstPublish >= 121 THEN 'Tier5'
ELSE 'Other' END 
END 
ELSE
CASE WHEN DaysSinceLastPublish IS NULL THEN NULL
WHEN DaysSinceLastPublish <= 30 THEN 'Tier1'
WHEN DaysSinceLastPublish <= 60 THEN 'Tier2'
WHEN DaysSinceLastPublish <= 90 THEN 'Tier3'
WHEN DaysSinceLastPublish <= 180 THEN 'Tier4'
WHEN DaysSinceLastPublish >= 181 THEN 'Tier5'
ELSE 'Other' END
END 
) BaseData
PIVOT
(count(ReservingToolID)
FOR DayTiers IN ([Tier1]
, [Tier2]
, [Tier3]
, [Tier4]
, [Tier5])
) as PivtTbl
ORDER BY PublishYear, PublishMonth, PublishOrder, HandledFromStartFlag
/*---- Drop temp table when query is done ---- */
IF OBJECT_ID('tempdb..#Temp_Timeliness') IS NOT NULL
/*Then it exists*/
DROP TABLE #Temp_Timeliness