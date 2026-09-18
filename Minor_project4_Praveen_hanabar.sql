 use redflag;
 SELECT COUNT(*) FROM redflag.transactions;
 -- TIER 1
 -- p1
 select user_id FROM transactions
 group by  user_id, DATE(txn_time)
 HAVING count( *) >=30;
 
 -- p2
 select user_id from transactions 
 where amount in(100,200,500,1000,2000,5000,10000)
 group by user_id
 having count(txn_id >=15);
 
 -- p3
 select user_id, date(txn_time) as txn_date,
 count(*) as total_transactions
 from transactions
 where amount < 10
 group by user_id, date(txn_time)
 having count(*) >= 30;
 
 -- p4
 select user_id, count(*) as total_failed_transactions
 from transactions where status = 'failed'
 group by user_id having count(*) >=20;
 
 -- p5
 select user_id from transactions
 group by user_id
 having count(*)>= 30
 and (sum(case when hour(txn_time) between 2 and 4 then 1 else 0 end) / count(*)) >= 0.80;
 
 -- TIER 2
 -- P6
  select c.user_id from transactions c
  where c.txn_type ='CREDIT'
  AND exists( select 1 from transactions d where d.user_id = c.user_id
  and d.txn_type = 'DEBIT'
  and d.txn_time > c.txn_time
  and d.txn_time <= c.txn_time + interval  30 minute
  and d.amount >= 0.70 * c.amount )
  group by c.user_id
  having count(*) >= 5;
  
  -- p7
  select user_id from transactions group by user_id
  having count(*) > 20
  and (sum(case when txn_type ='REFUND' THEN 1 ELSE 0 END) / COUNT(*)) > 0.40
  
  -- p8
    with user_merchant_volumes as (
   select merchant_id,user_id, sum(amount) as user_volume 
   from transactions group by merchant_id, user_id ),
   ranked_users as ( select merchant_id,user_volume,row_number() over(partition by   merchant_id order by user_volume desc) as user_rank
   from user_merchant_volumes),
   merchant_totals as (select merchant_id, sum(user_volume ) as total_merchant_volume,
   sum(case when user_rank <= 5 then user_volume else 0 end) as top_5_volume
   from ranked_users
   group by merchant_id)
select merchant_id, total_merchant_volume,top_5_volume,(top_5_volume / total_merchant_volume) * 100 as top_5_percentage
from merchant_totals
where (top_5_volume / total_merchant_volume) > 0.60
order by merchant_id
   
-- p9
select user_id, count(txn_id) as transaction_count,
sum(amount) as total_structured_amount
from transactions
where amount = 9999.00
group by user_id
having count(txn_id) >= 10
order by transaction_count desc;

-- p10
WITH transaction_history AS (
    SELECT 
        user_id,
        txn_time,
     
        DATEDIFF(
            txn_time, 
            LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time)
        ) AS date_gap_days,

        COUNT(*) OVER (
            PARTITION BY user_id 
            ORDER BY txn_time 
            ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
        ) AS post_gap_txn_count
    FROM transactions
)
SELECT 
    user_id,
    txn_time AS reactivation_time,
    post_gap_txn_count
FROM transaction_history
WHERE 
    (date_gap_days >= 90) 
    AND post_gap_txn_count >= 15
ORDER BY post_gap_txn_count DESC;

-- tier 3
-- 11
WITH total_dataset_months AS (
    -- Step 1: Count total unique months in the entire dataset
    SELECT COUNT(DISTINCT DATE_FORMAT(txn_time, '%Y-%m')) AS total_months
    FROM transactions
),

user_monthly_activity AS (
    SELECT 
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS txn_month,
        COUNT(*) AS monthly_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),

monthly_counts AS (
    SELECT 
        user_id,
        SUM(monthly_count) AS total_user_txns,
        MAX(monthly_count) AS peak_monthly_count,
        COUNT(DISTINCT txn_month) AS active_months_count
    FROM user_monthly_activity
    GROUP BY user_id
),

user_metrics AS (
    SELECT 
        m.user_id,
        m.peak_monthly_count,
        m.active_months_count,
        (CAST(m.total_user_txns AS DECIMAL(10,2)) / t.total_months) AS true_avg_monthly_count
    FROM monthly_counts m
    CROSS JOIN total_dataset_months t
)
SELECT 
    user_id,
    true_avg_monthly_count,
    peak_monthly_count,
    (peak_monthly_count / true_avg_monthly_count) AS spike_ratio
FROM user_metrics
WHERE peak_monthly_count >= 20 
  AND (peak_monthly_count / true_avg_monthly_count) >= 5
  AND active_months_count > 1;
  
  -- p12
  WITH ranked_transactions AS (
    SELECT 
        user_id,
        city,
        txn_time,
        LAG(city) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_city,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_time
    FROM 
        transactions
)
SELECT DISTINCT 
    user_id
FROM 
    ranked_transactions
WHERE 
    prev_city IS NOT NULL 
    AND city <> prev_city
    AND TIMESTAMPDIFF(MINUTE, prev_time, txn_time) <= 60;