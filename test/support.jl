using Inochi
using Test
using HTTP
using Base64

const InochiCore = Inochi.Core

const EXPECTED_SERVER_HEADER = "Inochi/" * Inochi.INOCHI_VERSION * " Julia/" * Inochi.JULIA_VERSION
const HTTP_DATE_PATTERN = r"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4} \d{2}:\d{2}:\d{2} GMT$"
