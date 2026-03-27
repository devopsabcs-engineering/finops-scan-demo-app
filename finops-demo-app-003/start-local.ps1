docker build -t finops-demo-003 .
docker run -d -p 8083:80 --name finops-demo-003 finops-demo-003
Write-Host "FinOps Demo App 003 running at http://localhost:8083" -ForegroundColor Green
