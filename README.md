# Crawl Pipeline

This application automates the process of crawling URLs sourced from a Google Sheet and archiving the content to Google Drive. It uses Elixir/Phoenix for orchestration and Oban for reliable background job processing, integrating with an external Python-based crawler.

## Architecture & Flow

The system operates in a pipeline:

1.  **Scheduled Sync (Oban Job)**:
    *   Runs on a schedule (cron-like).
    *   Fetches a specific Google Sheet.
    *   Extracts URLs from a **configurable column**.
    *   Compares with existing records (optional, depending on implementation) and enqueues **Crawl Jobs** for processing.

2.  **Crawl Worker (Oban Job)**:
    *   Picks up a URL.
    *   Executes an external Python script to perform the actual crawling and content generation.
    *   **External Tool**: Uses [crawler-ingest](https://github.com/www-zaq-ai/crawler-ingest).
    *   **Output**: Generates a Markdown file representing the page content, along with associated assets (PDFs, images).

3.  **Upload Worker (Oban Job)**:
    *   Triggered after a successful crawl.
    *   Takes the generated artifacts (Markdown + assets).
    *   Uploads them to a specific Google Drive folder.

## Software Stack

*   **Elixir & Phoenix**: Core application framework.
*   **Oban**: Robust background job processing and scheduling.
*   **Google Sheets API**: Source of truth for URLs.
*   **Google Drive API**: Storage destination for crawled content.
*   **Python**: Runtime for the actual crawling logic.
*   **crawler-ingest**: External Python repository used for the crawling logic ([link](https://github.com/www-zaq-ai/crawler-ingest)).

## Configuration

The application requires configuration for:

*   **Google Credentials**: Service account or OAuth tokens for Sheets and Drive access.
*   **Sheet ID**: The specific Google Sheet to monitor.
*   **URL Column**: The column letter (e.g., "A", "C") or header name where URLs are located.
*   **Drive Folder ID**: The destination folder in Google Drive.
*   **Python Path**: Location of the `crawler-ingest` script/virtual environment.

## Job Lifecycle

1.  **Sync**: `SheetWatcher` -> Enqueues `UrlCrawler` jobs.
2.  **Crawl**: `UrlCrawler` -> Runs Python script -> Enqueues `DriveUploader` jobs.
3.  **Upload**: `DriveUploader` -> Uploads to Drive -> Marks job complete.
