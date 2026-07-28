# External researcher Fabric SQL access via Azure Key Vault service principal
#
# Prerequisites:
#   1. Your account has Key Vault Secrets User access on uzima-secrets-xfmh
#   2. Run: az login --tenant 4fde8ff3-4dd5-42e1-a25a-e42905610d66
#   3. Install Microsoft ODBC Driver 18 for SQL Server
#
# This example authenticates once, opens one Fabric SQL connection, reuses it,
# then disconnects once at the end.

library(fabriconnect)

con <- connect_to_fabric_sql()
cat("Connected via Key Vault service-principal access.\n\n")

print(head(list_tables(con), 10))

participants <- read_table(
  con,
  "dbo.dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age")
)
print(head(participants, 10))

print(query_tables(con, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants"))

DBI::dbDisconnect(con)
cat("Connection closed.\n")
