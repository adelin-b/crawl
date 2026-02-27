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
    *   **External Tool**: Uses [crawler-ingest](https://github.com/www-zaq-ai/crawler-ingest). After fetching the tool, install its Python libraries with `pip install -r priv/python/crawler-ingest/requirements.txt`.
    *   **Output**: Generates a Markdown file representing the page content, along with associated assets (PDFs, images).

3.  **Upload Worker (Oban Job)**:
    *   Triggered after a successful crawl.
    *   Takes the generated artifacts (Markdown + assets).
    *   Uploads them to a specific Google Drive folder.
    *   Enqueues a **Webhook Worker** job upon successful upload.

4.  **Webhook Worker (Oban Job - Optional)**:
    *   If `UPLOAD_WEBHOOK_URL` is configured, sends a POST request to notify an external system.
    *   Includes the `root_google_drive_folder_id`, `url`, and `crawl_key` in the JSON payload.

## Software Stack

*   **Elixir & Phoenix**: Core application framework.
*   **Oban**: Robust background job processing and scheduling.
*   **Google Sheets API**: Source of truth for URLs.
*   **Google Drive API**: Storage destination for crawled content.
*   **Python**: Runtime for the actual crawling logic.
*   **crawler-ingest**: External Python repository used for the crawling logic ([link](https://github.com/www-zaq-ai/crawler-ingest)).

## External Python Tool Setup

Use the following commands to fetch and load the external crawler library:

```bash
mix crawl.python.fetch
python3 -m venv .venv
source .venv/bin/activate
pip install -r priv/python/crawler-ingest/requirements.txt
```

If you use a virtual environment, point Crawl to that Python executable so the installed libraries are available:

```elixir
config :crawl,
  python_executable: ".venv/bin/python"
```

If you fetched the crawler into a custom directory, also configure:

```elixir
config :crawl,
  crawler_ingest_path: "/absolute/path/to/crawler-ingest"
```

## Configuration

The application requires various environment variables to be set for it to run properly. 
You can copy `.env.example` to `.env` and edit the values, then source it before starting the application:

```bash
cp .env.example .env
source .env
```

Here are the environment variables that control the application:

### Google Integration
*   `GOOGLE_APPLICATION_CREDENTIALS_JSON`: The raw JSON string of your Google Cloud service account credentials used for Sheets and Drive access.
*   `GOOGLE_SHEET_ID`: The ID of the specific Google Sheet to monitor (from the URL).
*   `GOOGLE_SHEET_RANGE`: The range in the sheet to read/write (e.g., `Sheet1!A1:Z`).
*   `GOOGLE_SHEET_URL_HEADER`: The column header label where URLs are located (defaults to `website_url`).
*   `GOOGLE_SHEET_STATUS_HEADER`: The column header label for tracking progress (defaults to `status`).
*   `GOOGLE_DRIVE_FOLDER_ID`: The destination folder ID in Google Drive to upload crawled artifacts.
*   `UPLOAD_WEBHOOK_URL`: (Optional) The webhook endpoint to call after successful upload.

### External Crawler & AI
*   `SCALEWAY_API_KEY`: API key for Scaleway (used by the Python crawler for Pixtral image-to-text processing).

### Application & Database (Standard)
*   `CRAWL_ARTIFACT_DIR`: The absolute path to the directory where crawled zip files are temporarily stored (required in production, defaults to `/tmp/crawl_artifacts` in dev).
*   `DATABASE_URL`: Connection string to your PostgreSQL database (required in production).
*   `SECRET_KEY_BASE`: Secret key for Phoenix sessions (required in production).
*   `PORT`: Port to run the Phoenix application on (defaults to `4000`).

*(Note: **Python Path** and **Crawler Ingest Path** can be configured in your `config.exs` or `dev.exs` as described in the Setup section above).*

## Job Lifecycle

1.  **Sync**: `SheetWatcher` -> Enqueues `UrlCrawler` jobs.
2.  **Crawl**: `UrlCrawler` -> Runs Python script -> Enqueues `DriveUploader` jobs.
3.  **Upload**: `DriveUploader` -> Uploads to Drive -> Enqueues `Webhook Worker` job.
4.  **Webhook** (Optional): `Webhook Worker` -> POSTs JSON payload to external system.

### Webhook Payload Example

If `UPLOAD_WEBHOOK_URL` is configured, a JSON payload is sent upon successful upload to Drive:

```json
{
  "root_google_drive_folder_id": "1abcXYZ...",
  "url": "https://example.com",
  "crawl_key": "crawl_123_abc"
}
```

If `UPLOAD_WEBHOOK_URL` is unset or empty, this final webhook step is simply skipped.
