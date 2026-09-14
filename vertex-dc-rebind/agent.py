from google.cloud import storage

BUCKET = "vrp-vertex-privdelta-306778072080-20260914-085059"
OBJECT = "rebind-privdelta-20260914-090810.txt"
SOURCE = "REBIND_PRIVDELTA_20260914-090810"

class MarkerApp:
    def query(self, marker: str = ""):
        payload = (
            f"{SOURCE}\n"
            f"marker={marker}\n"
            f"bucket={BUCKET}\n"
            f"object={OBJECT}\n"
        )

        try:
            client = storage.Client()

            blob = (
                client
                .bucket(BUCKET)
                .blob(OBJECT)
            )

            blob.metadata = {
                "vrp-marker": SOURCE,
                "proof": "vertex-rebind-runtime-sa",
            }

            blob.upload_from_string(
                payload,
                content_type="text/plain",
            )

            return {
                "source": SOURCE,
                "marker": marker,
                "storage_write": "SUCCESS",
                "bucket": BUCKET,
                "object": OBJECT,
            }

        except Exception as exc:
            return {
                "source": SOURCE,
                "marker": marker,
                "storage_write": "ERROR",
                "error_type": type(exc).__name__,
                "error": str(exc)[:500],
                "bucket": BUCKET,
                "object": OBJECT,
            }

root_agent = MarkerApp()
