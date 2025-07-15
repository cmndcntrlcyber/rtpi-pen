-- RTPI-PEN Database Initialization Script
-- This script creates all required databases and users for the RTPI-PEN services

-- Create additional databases
CREATE DATABASE kasm;
CREATE DATABASE sysreptor;

-- Create users for different services
CREATE USER sysreptor WITH PASSWORD 'sysreptorpassword';
CREATE USER kasmapp WITH PASSWORD 'SjenXuTppFFSWIIKjaAJ';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE sysreptor TO sysreptor;
GRANT ALL PRIVILEGES ON DATABASE kasm TO kasmapp;
GRANT ALL PRIVILEGES ON DATABASE rtpi_main TO rtpi;

-- Create extensions if needed
\c sysreptor;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c kasm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c rtpi_main;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Log completion
\echo 'Database initialization completed successfully';
