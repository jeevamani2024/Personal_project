/* ---- Project 1 - Outstanding Publish SOLUTION ---- */
---- Run this query to create the procedure
---- then run the commented lines at the end to execute the procedure 
----   that includes the @Team parameter (more/less parameters optional)

CREATE PROCEDURE SPGetOutstandingRTPublish (
		@DaysToComplete AS INT = NULL,
		@DaysOverdue AS INT = NULL,
		@Office AS VARCHAR(32) = NULL, 
		@ManagerCode AS VARCHAR(32) = NULL, 
		@SupervisorCode AS VARCHAR(32) = NULL, 
		@ExaminerCode AS VARCHAR(32) = NULL, 
		@Team AS VARCHAR(32) = NULL,
		@ClaimsWithoutRTPublish AS BIT = 0
		)
AS
BEGIN

DECLARE @DateAsOf date
SET @DateAsOf = '1/1/2019'

declare @ReservingToolPbl table (ClaimNumber varchar(max), LastPublishedDate datetime)
declare @AssignedDateLog table (PK int, ExaminerAssignedDate datetime)

INSERT INTO @ReservingToolPbl 
SELECT ClaimNumber, max(EnteredOn) as LastPublishedDate
FROM Insurance.dbo.ReservingTool
where IsPublished = 1
group by ClaimNumber

insert into @AssignedDateLog (PK, ExaminerAssignedDate)
SELECT PK, max(EntryDate) as ExaminerAssignedDate
FROM Insurance.dbo.ClaimLog
where FieldName = 'examinercode'
group by PK

SELECT *
FROM
(
	SELECT ClaimNumber
		, ManagerCode
		, SupervisorCode
		, ExaminerCode
		, ManagerTitle
		, SupervisorTitle
		, ExaminerTitle
		, ManagerName
		, SupervisorName
		, ExaminerName
		, Office
		, ClaimStatusDesc
		, ClaimantName
		, ClaimantTypeDesc
		, ExaminerAssignedDate
		, ReopenedDate
		, AdjustedAssignedDate
		, LastPublishedDate
		, DaysSinceLastPublishedDate
		, DaysSinceAdjustedAssignedDate
		, CASE WHEN DaysSinceAdjustedAssignedDate >= 15 AND (DaysSinceLastPublishedDate >= 91 OR DaysSinceLastPublishedDate IS NULL) THEN 0
			WHEN 91 - DaysSinceLastPublishedDate >= 15 - DaysSinceAdjustedAssignedDate AND DaysSinceLastPublishedDate IS NOT NULL THEN 91 - DaysSinceLastPublishedDate
			ELSE 15 - DaysSinceAdjustedAssignedDate
			END AS DaysToComplete
		, CASE WHEN 14 >= DaysSinceAdjustedAssignedDate OR (90 >= DaysSinceLastPublishedDate AND DaysSinceLastPublishedDate IS NOT NULL) THEN 0
			WHEN DaysSinceLastPublishedDate - 90 <= DaysSinceAdjustedAssignedDate - 14 AND DaysSinceLastPublishedDate IS NOT NULL THEN DaysSinceLastPublishedDate - 90
			ELSE DaysSinceAdjustedAssignedDate - 14
			END AS DaysOverdue
		/* ALTERNATE WAY TO DO DaysToComplete AND DaysOverdue */
		/*
		, (SELECT MAX(DaysLeft1)
			FROM (VALUES (91 - DaysSinceLastPublishedDate),(15 - DaysSinceAdjustedAssignedDate),(0)) AS DaysUnder(DaysLeft1)) AS DaysToComplete
		, (SELECT MIN(DaysLeft2)
			FROM (VALUES (DaysSinceLastPublishedDate - 90),(DaysSinceAdjustedAssignedDate - 14)) AS DaysOver(DaysLeft2)) AS DaysOverdue
		*/
	FROM 
		(
		SELECT 
			C.ClaimNumber
			, R.ReserveAmount
			, Office.OfficeDesc as Office
			, U.UserName as ExaminerCode
			, users2.UserName as SupervisorCode
			, users3.UserName as ManagerCode
			, U.Title as ExaminerTitle
			, users2.Title as SupervisorTitle
			, users3.Title as ManagerTitle
			, CS.ClaimStatusDesc
			, P.LastName + ', ' + TRIM(P.FirstName + ' ' + P.MiddleName) AS ClaimantName
			, U.LastFirstName as ExaminerName
			, users2.lastfirstname as SupervisorName
			, users3.lastfirstname as ManagerName
			, CL.ReopenedDate
			, ADL.ExaminerAssignedDate
			, CASE WHEN CL.ClaimStatusID = 2 AND CL.ReopenedDate > ADL.ExaminerAssignedDate 
				THEN CL.ReopenedDate
				ELSE ADL.ExaminerAssignedDate
				END as AdjustedAssignedDate
			, CT.ClaimantTypeDesc
			, Office.State
			, U.ReserveLimit
			, (CASE 
				WHEN RT.parentid in (1,2,3,4,5,10) THEN RT.parentid 
				ELSE RT.ReserveTypeID END
				) AS ReserveCostID
			, RTP.LastPublishedDate
			, datediff(day, RTP.LastPublishedDate, @DateAsOf) as DaysSinceLastPublishedDate
			, CASE WHEN CL.ClaimStatusID = 2 AND CL.ReopenedDate > ADL.ExaminerAssignedDate 
				THEN datediff(day, CL.ReopenedDate, @DateAsOf)
				ELSE datediff(day, ADL.ExaminerAssignedDate, @DateAsOf) 
				END as DaysSinceAdjustedAssignedDate
		from Claimant CL
			INNER JOIN Claim C ON C.ClaimID=CL.ClaimID
			INNER JOIN [Users] U on U.Username = C.ExaminerCode
			INNER JOIN [Users] users2 on U.Supervisor = users2.UserName
			INNER JOIN [Users] users3 on users2.Supervisor = users3.UserName
			INNER JOIN [Office] on U.OfficeID = Office.OfficeID
			INNER JOIN ClaimantType CT ON CT.ClaimantTypeID=CL.ClaimantTypeID
			INNER JOIN Reserve R ON CL.ClaimantID=R.ClaimantID 
			LEFT JOIN ClaimStatus CS ON CS.ClaimStatusID=CL.ClaimStatusID
			LEFT JOIN ReserveType RT ON R.ReserveTypeID=RT.ReserveTypeID 
			LEFT JOIN Patient P ON P.PatientID=CL.PatientID
			LEFT JOIN @AssignedDateLog ADL ON ADL.PK = C.ClaimID
			LEFT JOIN @ReservingToolPbl RTP ON RTP.Claimnumber = C.Claimnumber
		WHERE
			(RT.parentid in (1,2,3,4,5,10) or RT.ReserveTypeID in (1,2,3,4,5,10))
			AND (CL.ClaimStatusID = 1 OR (CL.ClaimStatusID = 2 AND CL.ReopenedReasonID IN (1,2,4,5,6)))
			and office.OfficeDesc in ('Sacramento', 'San Francisco', 'San Diego')
		) as Basedata
		PIVOT
		(SUM(ReserveAmount)
			FOR ReserveCostID IN ([1],[2],[3],[4],[5],[10])
		) as PivTbl
	WHERE 
		ClaimantTypeDesc IN ('First Aid', 'Medical-Only')
		OR
			(Office = 'San Diego' 
				AND isnull([1],0) + isnull([2],0) + isnull([3],0) + isnull([4],0) + isnull([5],0) >= ReserveLimit
				AND ExaminerTitle LIKE '%analyst%'
			)
		OR
			(Office in ('Sacramento', 'San Francisco')
				AND (isnull([1],0) > 1000 
					or isnull([5],0) > 100 
					or (isnull([2],0) + isnull([3],0) + isnull([4],0) + isnull([10],0)) > 0
					)
			)
) MainQuery
WHERE (@DaysToComplete IS NULL OR DaysToComplete <= @DaysToComplete)
	AND (@DaysOverdue IS NULL OR DaysOverdue >= @DaysOverdue)
	AND (@Office IS NULL OR Office = @Office)
	AND (@ManagerCode IS NULL OR ManagerCode = @ManagerCode)
	AND (@SupervisorCode IS NULL OR SupervisorCode = @SupervisorCode)
	AND (@ExaminerCode IS NULL OR ExaminerCode = @ExaminerCode)
	AND (@Team IS NULL OR ExaminerTitle like '%' + @Team + '%'
			OR SupervisorTitle like '%' + @Team + '%'
			OR ManagerTitle like '%' + @Team + '%')
	AND (@ClaimsWithoutRTPublish = 0 OR LastPublishedDate IS NULL)
ORDER BY 
	ManagerCode
	, SupervisorCode
	, ExaminerCode
	, DaysOverdue DESC
	, DaysToComplete

END


SPGetOutstandingRTPublish @Team = 'Analyst'