# TheLook E-Commerce Analytics Case Study

SQL and BI analysis of the [BigQuery TheLook E-Commerce dataset](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce), examining customer behavior, retention and the hypothetical impact of a product change

## How to Run Queries

### Prerequisites

- Access to [Google BigQuery](https://console.cloud.google.com/bigquery)
- The public dataset `bigquery-public-data.thelook_ecommerce` (no setup needed)

### Running the Queries

1. Open BigQuery Console
2. Copy any query block from `SQL/part1_queries.sql`
3. Each task is seperated by comment headers (`-- Task A`, `-- Task B`, etc.)
4. Run each query independently - they are self-contained with their own CTEs

### Date Range Parameters

All queries use parameterized date logic. To modify:

- Find the `DATE('YYYY-MM-DD')` values in each query's `WHERE` clause
- Adjust `start_date` and `end_date` as needed

---

## Date Ranges Used

| Task                                  | Date Range                                  | Rationale                                            |
| ------------------------------------- | ------------------------------------------- | ---------------------------------------------------- |
| **Task A** (Monthly Financials) | 2019-01-01 to 2022-12-31                    | Full 4-year history for trend analysis               |
| **Task B** (New vs Returning)   | 2019-01-01 to 2022-12-31                    | Consistent with Task A for comparability             |
| **Task C** (90-Day Churn)       | 2019-01-01 to 2022-12-31 + 90-day lookahead | Extended window to calculate churn for Dec 2022      |
| **Task D** (Product Impact)     | 2021-10-15 to 2022-04-15                    | 3 months pre/post the hypothetical 2022-01-15 launch |

---

## Key Definitions & Assumptions

### Completed Sale

```
status = 'Complete' AND returned_at IS NULL
```

Only fully completed, non-returned orders count toward revenue and customer metrics.

### Month Grain

```sql
DATE_TRUNC(DATE(created_at), MONTH)
```

All monthly aggregations truncate to the first of the month.

### Revenue

```sql
SUM(sale_price)
```

From `order_items.sale_price`. Does not deduct COGS (gross revenue).

### Active Customer

A customer with **≥1 completed order** in a given month.

### New Customer

A customer whose **first-ever completed order** occurs in that month.

```sql
first_order_month = current_month
```

### Returning Customer

A customer who is **active in month M** but whose first order was in a **prior month**.

```sql
first_order_month < current_month AND has_order_in_current_month
```

### 90-Day Churn Definition

A customer is considered **churned from month M** if:

1. They were active in month M (had ≥1 completed order)
2. They have **no completed orders in the 90 days** following their last order date in month M

```sql
churned_90d = (next_order_date IS NULL OR next_order_date > last_order_date + 90 days)
```

#### Limitations of This Churn Definition

1. **Right-censoring bias**: Customers near the end of the dataset appear churned even if they would return later. Mitigated by extending the lookahead window
2. **No distinction by customer value**: A high ordering customer and a one-time buyer are treated equally. In production consider:

   - Weighted churn by customer value tier
   - Separate churn rates for cohorts (new vs. mature customers)
3. **Alternative refinements**:

   - Probabilistic churn models (survival analysis)
   - Engagement-based signals (email opens, site visits) before purchase gaps
   - Contractual vs. non-contractual churn frameworks

### Product Change Impact (Task D)

#### Hypothetical Scenario

On **2022-01-15**, a new checkout header was launched: *"Free shipping for orders over $100"*

#### Analysis Approach

Since the dataset doesn't reflect the actual change, we use proxy analysis:

1. **Pre/Post Comparison**: Orders before vs. after 2022-01-15
2. **High-Value Flag**: Orders ≥$100 as a proxy for "affected" segment
3. **Segment Breakdown**: By `traffic_source` to identify channel-specific impacts

#### Assumptions

- The promotion would primarily influence customers near the $100 threshold
- Traffic source behavior may differ (e.g., paid channels may show different elasticity)
- No actual shipping fee data exists; we simulate via order value proxy

#### Data Needed for Real Analysis

| Data Point              | Purpose                                |
| ----------------------- | -------------------------------------- |
| `shipping_fee` field  | Calculate actual savings per order     |
| Experiment assignment   | A/B test exposure for causal inference |
| Pre-checkout cart data  | Measure cart additions vs. completions |
| User session data       | Track threshold-seeking behavior       |
| Shipping cost by region | Understand margin impact               |

---

## Visualizations & Slides

### Links

- **Slides**: https://github.com/AdalgrimTook/thelook-ecom-case/blob/main/analysis/Thelook%20e-commerce-slides.pdf
- **Notebook**: See `analysis/visualizations.ipynb`

### Visuals Included

1. **New vs Returning Revenue Mix** — Monthly stacked area chart
2. **Monthly Churn Rate vs Revenue** — Dual-axis time series
3. **Free Shipping Impact** — Pre/Post AOV comparison by segment

---

## Key Insights & Recommendations

### Most Important Trend for Leadership

**90-day churn is at 95-100%** — Almost all customers don't return within 90 days. The business is heavily dependent on new customer acquisition. This indicates:

- Critical retention problem
- New customers drive 85-95% of revenue
- **Action**: Investigate root cause of churn and prioritize retention improvements

### Experiment Recommendation

**Targeted "Almost $100" Cart Reminder**

- **Hypothesis**: Users with carts between $80-$99 can be nudged to add items for free shipping
- **Target Segment**: Users from high Avg Order Value traffic sources (e.g., Email, Organic)
- **Primary Metric**: Conversion rate of $80-$99 carts to $100+ orders
- **Secondary Metrics**: Overall AOV, revenue per session, margin after shipping cost

### Suggested Product Health Dashboard (5-7 KPIs)

| Category               | Metric                                     |
| ---------------------- | ------------------------------------------ |
| **Acquisition**  | New customers per month                    |
| **Acquisition**  | Customer acquisition cost (CAC) by channel |
| **Activation**   | Time to first purchase (from signup)       |
| **Retention**    | 90-day churn rate                          |
| **Retention**    | Cohort retention at Month 3                |
| **Monetization** | Revenue (total & by new/returning)         |
| **Monetization** | Average Order Value (AOV)                  |

---

## Part 3: AI & Analytics

### How I Used AI Tools in This Challenge

#### SQL Optimization

- **Code optimization**: Used AI assistants to optimize for performance the queries on the initial tasks.
- **Documentation**: Generated initial README structure, then edited and expanded for accuracy

### Other possible AI Applications

- **Visualization suggestions**: Ask for chart type recommendations given the metrics
- **Summarization**: Used AI to draft executive summary bullets from query outputs
- **Routine metric interpretation**: When results are straightforward (e.g., "AOV increased 2.8%"), AI can quickly formulate the takeaway without needing human judgment, saves time on obvious conclusions

#### Example Prompt

```
Write a BigQuery SQL query that calculates 90-day churn rate per month. 
A customer is churned if they had an order in month X but no orders in the 
following 90 days. Use CTEs and window functions. The table is 
bigquery-public-data.thelook_ecommerce.order_items with columns: 
order_id, user_id, created_at, status, returned_at, sale_price.
```

#### How to Validate an AI Output

1. **Schema check**: Verify column names and types against actual BigQuery schema
2. **Logic review**: Trace CTEs step-by-step to make sure business logic matches definitions
3. **Edge cases**: Test with known scenarios (e.g., customer with exactly 90-day gap)
4. **Sample verification**: Run queries on small date ranges and manualy verified counts
5. **Consistency check**: Ensure metrics across tasks reconcile (e.g., Task A revenue ≈ Task B total revenue)

#### Key Principle

> **Trust but verify**: AI accelerates initial drafts, but everythinghas to be reviewed for business logic, and validated against the data before inclusion.

---

## Submission Checklist

- [X] GitHub repo with runnable SQL for all Part 1 tasks
- [X] README with definitions, assumptions, date ranges, how to run
- [X] AI usage documentation (Part 3)
- [X] Slides/notebook with 2-3 visuals
- [X] 2-3 clear recommendations documented

---

## Timeline & Contact

**Submitted**: 10/12/2025
**Author**: Pablo Fernandez
**Contact**: pablo.fdzt@gmail.com

