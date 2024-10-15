

select ClaimantID, ClaimID, EntryDate, ClosedDate, convert(int,EntryDate -ClosedDate) as Duration
from Claimant
where ClosedDate is not null
order by ClaimID

select sum(ReserveAmount) as Totalreserve from Reserve 

select  ExaminerCode, EnteredBy, year(EntryDate) as enty from Claim
group by  ExaminerCode

select reserveTypeID,  from ReserveType
select * from Reserve

4
select ClaimantID, count(*) as ReserveCount from Reserve
Group By ClaimantID
Having count(*)>= 15

5
select  right(FileName,4) as type1, count(1) as counts from Attachment
group by right(FileName,4)
order by count(right(FileName,4)) 

/*Select Project1 
At our insurance company, the examiners (aka claim specialists) are tasked with regularly using the Reserving Tool to help them estimate how much a given claim is going to cost the company.  There are lots of guidelines on how frequently an examiner should be using the Reserving Tool. An examiner has to use the reserving tool a certain number of days after the claim re-opens, after being assigned the claim, or after an examiner last used the Reserving Tool on that claim.
Our job is to determine how long an examiner has until they are required to use the Reserving Tool, and if they are already past their due date, how many days they have been overdue.  And we will need to do this for all the claims assigned to all of our examiners.
*/

select ClaimantID, ReopenedDate from Claimant

select PK, max(EntryDate)  as ExaminerAssignedDate
from  ClaimLog
where FieldName = 'ExaminerCode'
Group by PK

Select ClaimNumber, max(EnteredOn) as LastSavedOn
From ReservingTool
where IsSaved = 1
Group by ClaimNumber


select * from ClaimStatus
select *from Claimant
inner join ClaimStatus on Claimant.claimStatusID = ClaimStatus.ClaimStatusID


select  from claim
select * from ReservingTool