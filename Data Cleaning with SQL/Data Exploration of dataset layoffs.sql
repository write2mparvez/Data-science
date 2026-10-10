Data Exploration in SQL
-- ==============================================================================
-- WORLD LAYOFFS - EXPLORATORY DATA ANALYSIS (EDA) SCRIPT
-- ==============================================================================
-- Objective: 
-- Now that our data is clean, we want to dig into it and uncover real-world trends. 
-- We want to answer the big questions: Who got hit hardest? When did it spike? 
-- What did the progression look like over time?
-- Note: We are strictly using our fully polished production table: `layoffs_staging2`.
-- ==============================================================================
---------------------------------------------------------------------------------------------------------
-- PHASE 1: HIGH-LEVEL INSPECTION & EXTREMES
-- Goal: Get a feel for the dataset bounds and check out the absolute worst-case scenarios.
---------------------------------------------------------------------------------------------------------

-- Step 1.1: Quick sanity check to view the structure of our clean data.
SELECT * 
FROM world_layoffs.layoffs_staging2;

-- Step 1.2: Find the largest single layoff event and the highest percentage laid off.
-- Why: This sets our baseline extremes. A percentage of '1' means a 100% company shutdown.
SELECT 
    MAX(total_laid_off) AS absolute_max_layoffs, 
    MAX(percentage_laid_off) AS max_percentage_lost
FROM world_layoffs.layoffs_staging2;

-- Step 1.3: Look at companies that completely shut down (100% layoffs).
-- Why: We sort by funding ('funds_raised_millions') to see which highly-funded startups collapsed entirely.
SELECT *
FROM world_layoffs.layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY funds_raised_millions DESC;


---------------------------------------------------------------------------------------------------------
-- PHASE 2: CORE AGGREGATIONS (WHO TOOK THE HEAVIEST BLOWS?)
-- Goal: Roll up individual tracking records into grand totals by entity, industry, and geography.
---------------------------------------------------------------------------------------------------------

-- Step 2.1: Total layoffs by Company across the entire timeline.
-- Why: Individual rows show distinct layoff events. Running a SUM() gives us the true cumulative job losses per brand.
SELECT 
    company, 
    SUM(total_laid_off) AS total_employees_lost
FROM world_layoffs.layoffs_staging2
GROUP BY company
ORDER BY total_employees_lost DESC;

-- Step 2.2: Total layoffs by Industry.
-- Why: Helps us see which sector faced the most severe economic downturn (e.g., Tech, Finance, Retail).
SELECT 
    industry, 
    SUM(total_laid_off) AS total_employees_lost
FROM world_layoffs.layoffs_staging2
GROUP BY industry
ORDER BY total_employees_lost DESC;

-- Step 2.3: Total layoffs by Country.
-- Why: Gives global context to see where the vast majority of these corporate job losses occurred geographically.
SELECT 
    country, 
    SUM(total_laid_off) AS total_employees_lost
FROM world_layoffs.layoffs_staging2
GROUP BY country
ORDER BY total_employees_lost DESC;


---------------------------------------------------------------------------------------------------------
-- PHASE 3: TEMPORAL TRAJECTORY (THE TIMELINE FACTORS)
-- Goal: Look at how layoffs fluctuated across different calendar years and startup maturity stages.
---------------------------------------------------------------------------------------------------------

-- Step 3.1: Layoffs by Calendar Year.
-- Why: We use YEAR(`date`) to isolate the chronological cycle. This highlights exactly which year hit the global workforce the hardest.
SELECT 
    YEAR(`date`) AS calendar_year, 
    SUM(total_laid_off) AS total_employees_lost
FROM world_layoffs.layoffs_staging2
GROUP BY YEAR(`date`)
ORDER BY calendar_year DESC;

-- Step 3.2: Layoffs by Company Funding Stage (e.g., Series A, Seed, Post-IPO).
-- Why: Tells us if mature, public corporations (Post-IPO) or early, fragile startups were letting more people go.
SELECT 
    stage, 
    SUM(total_laid_off) AS total_employees_lost
FROM world_layoffs.layoffs_staging2
GROUP BY stage
ORDER BY total_employees_lost DESC;


---------------------------------------------------------------------------------------------------------
-- PHASE 4: TIME-SERIES RUNNING CALCULATIONS (MONTH-OVER-MONTH ROLLING TOTAL)
-- Goal: Calculate a continuous rolling tally of global layoffs to plot an ongoing growth curve.
---------------------------------------------------------------------------------------------------------

-- Step 4.1: Establish a baseline month-by-month summary using a CTE, then apply a window function.
-- Why: A standard GROUP BY collapses rows, preventing us from viewing a continuous run tally. 
-- By wrapping the month aggregations inside a CTE called 'Rolling_Total_CTE', we can cleanly scan over it.
WITH Rolling_Total_CTE AS (
    -- Sub-step: Extract Year-Month strings (YYYY-MM) and sum layoffs within each isolated month
    SELECT 
        SUBSTRING(`date`, 1, 7) AS layoff_month, 
        SUM(total_laid_off) AS monthly_losses
    FROM world_layoffs.layoffs_staging2
    WHERE SUBSTRING(`date`, 1, 7) IS NOT NULL
    GROUP BY layoff_month
    ORDER BY layoff_month ASC
)
-- Main wrapper calculation: Scan over our months and accumulate a running sum
SELECT 
    layoff_month, 
    monthly_losses,
    -- The Window Function: SUM() combined with OVER(ORDER BY...) acts as our progressive calculator.
    -- It adds the current month's losses to the running sum of all previous records in the list.
    SUM(monthly_losses) OVER(ORDER BY layoff_month) AS cumulative_rolling_total
FROM Rolling_Total_CTE;


---------------------------------------------------------------------------------------------------------
-- PHASE 5: THE ANNUAL LEADERS PANEL (TOP 5 HIGHEST LAYOFFS PER YEAR)
-- Goal: Isolate and rank the top 5 corporations with the most job cuts for every separate calendar year.
---------------------------------------------------------------------------------------------------------

-- Step 5.1: Chain two sequential CTEs to overcome standard SQL filtering limits.
-- Why: SQL rules do not allow window function rankings to be filtered directly inside a WHERE clause.
-- We use a two-step virtual staging pipeline to pull this off seamlessly.

-- CTE 1 (Company_Year): Roll up total layoffs for every company, explicitly separated by year.
WITH Company_Year (company, years, total_laid_off) AS (
    SELECT 
        company, 
        YEAR(`date`), 
        SUM(total_laid_off)
    FROM world_layoffs.layoffs_staging2
    GROUP BY company, YEAR(`date`)
), 

-- CTE 2 (Company_Year_Rank): Take that yearly list and rank the companies within their respective year.
Company_Year_Rank AS (
    SELECT 
        *, 
        -- The Window Function: DENSE_RANK() builds our integer rank leaderboard (1, 2, 3...).
        -- PARTITION BY years: Splits the leaderboard into separate buckets for each calendar year.
        -- ORDER BY total_laid_off DESC: Sorts the companies inside each year from highest layoffs to lowest.
        DENSE_RANK() OVER (PARTITION BY years ORDER BY total_laid_off DESC) AS ranking_position
    FROM Company_Year
    WHERE years IS NOT NULL
)

-- Final Outer Selection: Query our rank table to pull out only the absolute leaders.
-- Why: Now that 'ranking_position' is a structured column from our CTE, we can filter it down to the Top 5.
SELECT * 
FROM Company_Year_Rank
WHERE ranking_position <= 5
ORDER BY years ASC, ranking_position ASC;
