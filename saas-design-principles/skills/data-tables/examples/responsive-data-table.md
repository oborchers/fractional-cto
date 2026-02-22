# Responsive Data Table

Demonstrates proper alignment, URL-based pagination, bulk selection, and table-to-card conversion on mobile.

## CSS: Alignment and Typography

```css
/* Core alignment rules — non-negotiable */
.table th,
.table td {
  text-align: left;              /* Default: left-align text */
  padding: 12px 16px;
}

.table th.numeric,
.table td.numeric {
  text-align: right;             /* Right-align numbers */
  font-variant-numeric: tabular-nums;  /* Equal-width digits */
  font-family: "JetBrains Mono", "SF Mono", monospace;
}

/* Never center-align data columns */

/* Header alignment must match content */
.table th.numeric { text-align: right; }
```

## Pseudocode: URL-Based Pagination

```
component PaginatedTable(data, columns):
    // Read pagination state from URL
    params = getUrlParams()
    page = parseInt(params.page) || 1
    perPage = parseInt(params.perPage) || 20
    sortBy = params.sortBy || columns[0].key
    sortDir = params.sortDir || "asc"

    totalItems = data.totalCount
    totalPages = ceil(totalItems / perPage)
    items = data.items

    function goToPage(newPage):
        // Update URL — preserves filters, sorting, and pagination in browser history
        setUrlParams({ ...params, page: newPage })

    function toggleSort(columnKey):
        if sortBy == columnKey:
            setUrlParams({ ...params, sortDir: sortDir == "asc" ? "desc" : "asc" })
        else:
            setUrlParams({ ...params, sortBy: columnKey, sortDir: "asc", page: 1 })

    render:
        <table>
            <thead>
                <tr>
                    for column in columns:
                        <th
                            class={column.numeric ? "numeric" : ""}
                            aria-sort={sortBy == column.key ? sortDir : "none"}
                            onClick={() => toggleSort(column.key)}
                        >
                            {column.label}
                        </th>
                </tr>
            </thead>
            <tbody>
                for item in items:
                    <tr>
                        for column in columns:
                            <td class={column.numeric ? "numeric" : ""}>
                                {formatCell(item[column.key], column)}
                            </td>
                    </tr>
            </tbody>
        </table>

        <Pagination
            currentPage={page}
            totalPages={totalPages}
            totalItems={totalItems}
            onPageChange={goToPage}
        />
```

## Bulk Selection

```
component SelectableTable(items, bulkActions):
    state selectedIds = Set()

    function toggleRow(id):
        if selectedIds.has(id):
            selectedIds.delete(id)
        else:
            selectedIds.add(id)

    function selectAllOnPage():
        for item in currentPageItems:
            selectedIds.add(item.id)

    function selectAllAcrossPages():
        // Separate action — never conflate with "select all on this page"
        selectedIds = Set(allItemIds)

    render:
        if selectedIds.size > 0:
            <BulkActionBar>
                <span>{selectedIds.size} selected</span>
                {selectedIds.size < totalItems &&
                    <button onClick={selectAllAcrossPages}>
                        Select all {totalItems} items
                    </button>
                }
                for action in bulkActions:
                    <button onClick={() => action.handler(selectedIds)}>
                        {action.label}
                    </button>
            </BulkActionBar>

        <table>
            <thead>
                <tr>
                    <th>
                        <checkbox
                            checked={allOnPageSelected}
                            onChange={selectAllOnPage}
                            aria-label="Select all on this page"
                        />
                    </th>
                    ...columns
                </tr>
            </thead>
            ...
        </table>
```

## Mobile: Table-to-Card Conversion

```css
/* Desktop: standard table */
@media (min-width: 768px) {
  .responsive-table { display: table; }
  .responsive-table .card-view { display: none; }
}

/* Mobile: convert to cards */
@media (max-width: 767px) {
  .responsive-table table { display: none; }

  .responsive-table .card-view {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .data-card {
    border: 1px solid var(--color-border-default);
    border-radius: var(--radius-default);
    padding: 16px;
  }

  .data-card .card-header {
    font-weight: 600;
    margin-bottom: 8px;
  }

  .data-card .card-row {
    display: flex;
    justify-content: space-between;
    padding: 4px 0;
  }

  .data-card .card-label {
    color: var(--color-text-secondary);
    font-size: 0.875rem;
  }

  /* Hide bulk actions below 490px unless essential */
  .bulk-action-bar { display: none; }
}
```

## Alternative: Horizontal Scroll with Frozen Column

Use when column relationships matter more than individual record browsing:

```css
.scroll-table-wrapper {
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

.scroll-table th:first-child,
.scroll-table td:first-child {
  position: sticky;
  left: 0;
  background: var(--color-bg-surface);
  z-index: 1;
  border-right: 2px solid var(--color-border-default);
}
```

## Key Points

- **Left-align text, right-align numbers, match headers to content, never center-align**
- **Tabular-nums** for number columns so digits have equal width
- **Pagination state in the URL** — users can bookmark, share, and use browser back
- **10–20 items per page**, total count always visible
- **"Select all on page" and "select all across pages" are separate actions**
- **Below 768px**: convert to cards (for browsing) or frozen-column scroll (for comparing)
- **Below 490px**: hide bulk actions unless essential
