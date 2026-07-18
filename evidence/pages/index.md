---
title: Retail Revenue
---

# Online Retail — Revenue Dashboard

Built on the `fct_revenue` gold mart: one row per completed (non-cancelled,
positively-priced) transaction line from the UK gift retailer's Dec 2010–Dec
2011 sales.

```sql kpis
select
    sum(line_amount)               as total_revenue,
    count(distinct invoice_no)     as total_orders,
    count(distinct customer_id)    as total_customers
from retail.fct_revenue
```

<BigValue data={kpis} value=total_revenue fmt='gbp0' title="Total Revenue"/>
<BigValue data={kpis} value=total_orders fmt='#,##0' title="Orders"/>
<BigValue data={kpis} value=total_customers fmt='#,##0' title="Unique Customers"/>

## Revenue over time

```sql countries
select country
from retail.fct_revenue
group by country
order by country
```

<Dropdown data={countries} name=country value=country title="Country">
    <DropdownOption value="%" valueLabel="All Countries"/>
</Dropdown>

```sql revenue_by_month
select
    invoice_month,
    sum(line_amount) as revenue
from retail.fct_revenue
where country like '${inputs.country.value}'
group by 1
order by 1
```

<LineChart
    data={revenue_by_month}
    x=invoice_month
    y=revenue
    yFmt='gbp0'
    title="Revenue by Month — {inputs.country.label}"
/>

## Top products and markets

```sql top_products
select
    description,
    sum(line_amount) as revenue
from retail.fct_revenue
where description is not null
group by 1
order by 2 desc
limit 10
```

<BarChart
    data={top_products}
    x=description
    y=revenue
    xFmt='gbp0'
    swapXY=true
    title="Top 10 Products by Revenue"
/>

```sql revenue_by_country
select
    country,
    sum(line_amount) as revenue
from retail.fct_revenue
group by 1
order by 2 desc
limit 10
```

<BarChart
    data={revenue_by_country}
    x=country
    y=revenue
    xFmt='gbp0'
    swapXY=true
    title="Top 10 Countries by Revenue"
/>

## Data quality

Row counts across the medallion layers — what got loaded, what Silver
deduped/typed, and what Silver's explicit business rules (cancelled orders,
non-positive quantity/price) excluded before Gold.

```sql data_quality
select check_name, row_count
from retail.data_quality
order by row_count desc
```

<DataTable data={data_quality} rows=10>
    <Column id=check_name title="Check"/>
    <Column id=row_count title="Row Count" fmt='#,##0'/>
</DataTable>
