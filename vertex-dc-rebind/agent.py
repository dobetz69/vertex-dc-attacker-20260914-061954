class MarkerApp:
    def query(self, marker: str = ""):
        return {
            "source": "ACTAS_SOURCE_20260914-083837",
            "marker": marker,
        }

root_agent = MarkerApp()
