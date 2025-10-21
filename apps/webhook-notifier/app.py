#!/usr/bin/env python3
"""Simple webhook receiver for *Arr notifications"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, os

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode()
        data = json.loads(body)
        
        # Extract event info
        event_type = data.get('eventType', 'Unknown')
        series = data.get('series', {}).get('title') or data.get('movie', {}).get('title', 'Unknown')
        
        # Send notification
        os.system(f'bash scripts/phase2/send_alert.sh info "Media Ready" "{series} is ready to watch!"')
        
        self.send_response(200)
        self.end_headers()
        
    def log_message(self, format, *args):
        pass  # Quiet logging

if __name__ == '__main__':
    HTTPServer(('0.0.0.0', 8090), WebhookHandler).serve_forever()
