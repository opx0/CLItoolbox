      
#!/bin/bash

# Check Docker version
docker --version > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Docker not found. Installation may be incomplete."
  exit 1
fi

# Check Docker daemon status
systemctl status docker > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Docker daemon is not running. Try 'sudo systemctl start docker'."
  exit 1
fi

# Run a simple container test
docker run hello-world > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Error running 'hello-world' container. Docker may not be working correctly."
  exit 1
fi

echo "Docker seems to be installed and working correctly!"

    
