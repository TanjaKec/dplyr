context("SQL translation")

test_that("Simple maths is correct", {
  expect_equal(translate_sql(1 + 2), sql("1.0 + 2.0"))
  expect_equal(translate_sql(2 * 4), sql("2.0 * 4.0"))
  expect_equal(translate_sql(5 ^ 2), sql("POWER(5.0, 2.0)"))
  expect_equal(translate_sql(100L %% 3L), sql("100 % 3"))
})

test_that("small numbers aren't converted to 0", {
  expect_equal(translate_sql(1e-9), sql("1e-09"))
})

test_that("logical values are converted to 0/1/NULL", {
  expect_equal(translate_sql(FALSE), sql("0"))
  expect_equal(translate_sql(TRUE), sql("1"))
  expect_equal(translate_sql(NA), sql("NULL"))
})

test_that("dplyr.strict_sql = TRUE prevents auto conversion", {
  old <- options(dplyr.strict_sql = TRUE)
  on.exit(options(old))

  expect_equal(translate_sql(1 + 2), sql("1.0 + 2.0"))
  expect_error(translate_sql(blah(x)), "could not find function")
})

test_that("Wrong number of arguments raises error", {
  expect_error(translate_sql(mean(1, 2), window = FALSE), "Invalid number of args")
})

test_that("Named arguments generates warning", {
  expect_warning(translate_sql(mean(x = 1), window = FALSE), "Named arguments ignored")
})

test_that("between translated to special form (#503)", {

  out <- translate_sql(between(x, 1, 2))
  expect_equal(out, sql('"x" BETWEEN 1.0 AND 2.0'))
})

test_that("is.na and is.null are equivalent", {
  # Needs to be wrapped in parens to ensure correct precedence
  expect_equal(translate_sql(is.na(x)), sql('(("x") IS NULL)'))
  expect_equal(translate_sql(is.null(x)), sql('(("x") IS NULL)'))

  expect_equal(translate_sql(x + is.na(x)), sql('"x" + (("x") IS NULL)'))
  expect_equal(translate_sql(!is.na(x)), sql('NOT((("x") IS NULL))'))
})

test_that("if translation adds parens", {
  expect_equal(
    translate_sql(if (x) y),
    sql('CASE WHEN ("x") THEN ("y") END')
  )
  expect_equal(
    translate_sql(if (x) y else z),
    sql('CASE WHEN ("x") THEN ("y") ELSE ("z") END')
  )
})

test_that("if and ifelse use correctly named arguments",{
  exp <- translate_sql(if (x) 1 else 2)

  expect_equal(translate_sql(ifelse(test = x, yes = 1, no = 2)), exp)
  expect_equal(translate_sql(if_else(condition = x, true = 1, false = 2)), exp)
})

test_that("pmin and pmax become min and max", {
  expect_equal(translate_sql(pmin(x, y)), sql('MIN("x", "y")'))
  expect_equal(translate_sql(pmax(x, y)), sql('MAX("x", "y")'))
})

test_that("%in% translation parenthesises when needed", {
  expect_equal(translate_sql(x %in% 1L), sql('"x" IN (1)'))
  expect_equal(translate_sql(x %in% 1:2), sql('"x" IN (1, 2)'))
  expect_equal(translate_sql(x %in% y), sql('"x" IN "y"'))
})

# Minus -------------------------------------------------------------------

test_that("unary minus flips sign of number", {
  expect_equal(translate_sql(-10L), sql("-10"))
  expect_equal(translate_sql(x == -10), sql('"x" = -10.0'))
  expect_equal(translate_sql(x %in% c(-1L, 0L)), sql('"x" IN (-1, 0)'))
})

test_that("unary minus wraps non-numeric expressions", {
  expect_equal(translate_sql(-(1L + 2L)), sql("-(1 + 2)"))
  expect_equal(translate_sql(-mean(x), window = FALSE), sql('-AVG("x")'))
})

test_that("binary minus subtracts", {
  expect_equal(translate_sql(1L - 10L), sql("1 - 10"))
})

# Window functions --------------------------------------------------------

test_that("window functions without group have empty over", {
  expect_equal(translate_sql(n()), sql("COUNT(*) OVER ()"))
  expect_equal(translate_sql(sum(x)), sql('sum("x") OVER ()'))
})

test_that("aggregating window functions ignore order_by", {
  expect_equal(
    translate_sql(n(), vars_order = "x"),
    sql("COUNT(*) OVER ()")
  )
  expect_equal(
    translate_sql(sum(x), vars_order = "x"),
    sql('sum("x") OVER ()')
  )
})

test_that("cumulative windows warn if no order", {
  expect_warning(translate_sql(cumsum(x)), "does not have explicit order")
  expect_warning(translate_sql(cumsum(x), vars_order = "x"), NA)
})

test_that("ntile always casts to integer", {
  expect_equal(
    translate_sql(ntile(x, 10.5)),
    sql('NTILE(10) OVER (ORDER BY "x")')
  )
})

test_that("connection affects quoting character", {
  dbiTest <- structure(list(), class = "DBITestConnection")
  dbTest <- src_sql("test", con = dbiTest)
  testTable <- tbl_sql("test", src = dbTest, from = "table1")

  out <- select(testTable, field1)
  expect_match(sql_render(out), "^SELECT `field1` AS `field1`\nFROM `table1`$")
})


# log ---------------------------------------------------------------------

test_that("log base comes first", {
  expect_equal(translate_sql(log(x, 10)), sql('log(10.0, "x")'))
})

test_that("sqlite mimics two argument log", {
  translate_sqlite <- function(...) {
    translate_sql(..., con = src_memdb()$obj)
  }

  expect_equal(translate_sqlite(log(x)), sql('log(`x`)'))
  expect_equal(translate_sqlite(log(x, 10)), sql('log(`x`) / log(10.0)'))
})

# partial_eval() ----------------------------------------------------------

test_that("subsetting always evaluated locally", {
  x <- list(a = 1, b = 1)
  y <- c(2, 1)
  correct <- quote(`_var` == 1)

  expect_equal(partial_eval(quote(`_var` == x$a)), correct)
  expect_equal(partial_eval(quote(`_var` == x[[2]])), correct)
  expect_equal(partial_eval(quote(`_var` == y[2])), correct)
})

test_that("namespace operators always evaluated locally", {
  expect_equal(partial_eval(quote(base::sum(1, 2))), 3)
  expect_equal(partial_eval(quote(base:::sum(1, 2))), 3)
})
