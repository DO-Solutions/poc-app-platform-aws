# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /code

# Copy the dependencies file to the working directory
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Install AWS IAM Roles Anywhere credential helper
RUN apt-get update && apt-get install -y wget \
    && wget -O /usr/local/bin/aws_signing_helper https://rolesanywhere.amazonaws.com/releases/1.1.1/X86_64/Linux/aws_signing_helper \
    && chmod +x /usr/local/bin/aws_signing_helper \
    && apt-get remove -y wget \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy the rest of the application code
COPY . .

# Default command runs the API
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
