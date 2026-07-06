"""Generate a 1-page instruction sheet for researchers."""

from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
import os


def generate():
    doc = Document()

    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("\n\nUZIMA Fabric Data Access\n")
    run.font.size = Pt(22)
    run.bold = True

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("Quick Start Guide\n")
    run.font.size = Pt(14)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run("\nEverything is pre-configured on this VM.\nJust open RStudio or Python and run the code below.\n")
    run.font.size = Pt(11)

    doc.add_heading("RStudio", level=2)
    doc.add_paragraph("Create a new R Markdown (.Rmd) file and paste this in any code chunk:")
    _code(doc, [
        "```{r}",
        "library(fabriconnect)",
        "conn <- connect_to_fabric()",
        "",
        "# List all tables",
        "tables <- list_tables(conn)",
        "",
        "# Read a table",
        'df <- read_table(conn, "registeredparticipants")',
        "head(df)",
        "```",
    ])
    doc.add_paragraph("That's it. No login, no token setup, nothing else needed.")

    doc.add_heading("Python", level=2)
    doc.add_paragraph("In a terminal or notebook:")
    _code(doc, [
        "from fabricpy import FabricLakehouse",
        "lh = FabricLakehouse()",
        "tables = lh.list_tables()",
        'df = lh.read_table("agents").to_pandas()',
        "df.head()",
    ])

    doc.add_heading("Test It", level=2)
    doc.add_paragraph("Run one of these to verify everything works:")
    _code(doc, [
        '# RStudio:',
        'source("Runbooks/test-r-access.R")',
        '',
        '# Or in a terminal:',
        'python test_delegated_access.py',
    ])

    doc.add_heading("What's Available", level=2)
    doc.add_paragraph(
        "You have access to the primary lakehouse (uzima_db_backup) with 31 tables "
        "containing Fitbit activity/sleep data, survey results (Qualtrics), "
        "participant records, and study agent assignments."
    )
    doc.add_paragraph("Key tables:")
    for name, desc in [
        ("agents", "Study agent assignments"),
        ("dimdate", "Date dimension for time-based analysis"),
        ("dimenrolledparticipants", "Core participant enrolment details"),
        ("dimsleepdetailslogs", "Sleep log data"),
        ("dimsurveyresults", "Survey responses"),
        ("dimsurveytask", "Survey task assignments"),
        ("factfitbitdailydata", "Daily Fitbit summaries (steps, calories, etc.)"),
        ("factfitbitsleeplogs", "Fitbit sleep session logs"),
        ("factfitbitrestingheartrates", "Fitbit resting heart rate data"),
        ("qualtrics_hcw_student_survey", "Qualtrics survey data"),
        ("registeredparticipants", "Registered participant records"),
    ]:
        p = doc.add_paragraph(style="List Bullet")
        run = p.add_run(name + ": ")
        run.bold = True
        p.add_run(desc)

    doc.add_heading("Source Code", level=2)
    doc.add_paragraph("This setup is open-source. Code and docs:")
    _code(doc, ["https://github.com/AKU-CDIO/fabric-inbound-access"])

    doc.add_heading("Need help?", level=2)
    doc.add_paragraph("Contact Derick Imbati  \u2014  derick.imbati@aku.edu")

    output_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "UZIMA_Fabric_Access_Instructions.docx",
    )
    doc.save(output_path)
    print(f"Saved: {output_path}")


def _code(doc, lines):
    for line in lines:
        p = doc.add_paragraph()
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        run = p.add_run(line)
        run.font.name = "Consolas"
        run.font.size = Pt(9)


if __name__ == "__main__":
    generate()
