class MarkerApp:
    def query(self, marker: str = ""):
        return {
            "source": "ATTACKER_MARKER",
            "marker": marker,
        }

root_agent = MarkerApp()
