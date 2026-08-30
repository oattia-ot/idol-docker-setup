FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the port
EXPOSE 5000

# Run the Flask development server (for demo/monitoring UI)
# In production, consider using gunicorn: gunicorn -w 4 -b 0.0.0.0:5000 server:app
CMD ["python", "server.py"]
