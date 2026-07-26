library(quantmod); library(dplyr); library(MASS); library(copula)
set.seed(2020)
dir.create("report_figures", showWarnings = FALSE)
tickers <- c("JPM","BAC","WFC","XOM","CVX","COP","AAPL","MSFT","NVDA","AMZN","HD","MCD")
sector <- rep(c("Financials","Energy","Technology","Consumer"), each = 3)
company <- c("JPMorgan Chase & Co.","Bank of America Corporation","Wells Fargo & Company",
             "Exxon Mobil Corporation","Chevron Corporation","ConocoPhillips",
             "Apple Inc.","Microsoft Corporation","NVIDIA Corporation",
             "Amazon.com, Inc.","The Home Depot, Inc.","McDonald's Corporation")
universe <- data.frame(ticker = tickers, sector, company)

# 1. Download adjusted prices and retain common trading days.
if (file.exists("covid_clean_adjusted_prices.csv")) {
  clean <- read.csv("covid_clean_adjusted_prices.csv")
  clean$date <- as.Date(clean$date)
} else {
  raw <- bind_rows(lapply(seq_along(tickers), function(i) {
    x <- getSymbols(tickers[i], src = "yahoo", from = "2018-12-01",
                    to = "2021-12-31", auto.assign = FALSE)
    data.frame(date = as.Date(index(x)), ticker = tickers[i],
               sector = sector[i], company = company[i],
               adjusted_price = as.numeric(Ad(x)))
  }))
  clean <- raw |> filter(is.finite(adjusted_price), adjusted_price > 0) |>
    distinct(date, ticker, .keep_all = TRUE) |>
    group_by(date) |> filter(n_distinct(ticker) == length(tickers)) |>
    ungroup() |> arrange(ticker, date)
  write.csv(clean, "covid_clean_adjusted_prices.csv", row.names = FALSE)
}

# 2. Returns, outliers, largest moves, diagnostics and plots.
ret <- clean |> group_by(ticker) |> arrange(date, .by_group = TRUE) |>
  mutate(log_return = log(adjusted_price / lag(adjusted_price)),
         z = (log_return - mean(log_return, na.rm = TRUE)) /
             sd(log_return, na.rm = TRUE)) |> ungroup()
largest <- ret |> filter(is.finite(log_return)) |> group_by(ticker) |>
  slice_max(abs(log_return), n = 1, with_ties = FALSE) |> ungroup()
write.csv(largest, "covid_largest_move_dates.csv", row.names = FALSE)
label_moves <- largest |> filter(ticker != "AMZN") |> bind_rows(
  ret |> filter(ticker == "AMZN", date == as.Date("2020-03-12")))

diag_one <- function(x) {
  x <- x[is.finite(x)]; n <- length(x); s <- sd(x)
  sk <- mean((x - mean(x))^3) / s^3
  ek <- mean((x - mean(x))^4) / s^4 - 3
  jb <- n / 6 * (sk^2 + ek^2 / 4)
  data.frame(n, skewness = sk, excess_kurtosis = ek,
             JB = jb, JB_p = pchisq(jb, 2, lower.tail = FALSE))
}
normality <- ret |> group_by(ticker, sector) |>
  group_modify(~diag_one(.x$log_return)) |> ungroup()
write.csv(normality, "covid_return_normality_summary.csv", row.names = FALSE)

bg <- "#EFF6FF"; reps <- c("JPM","COP","AAPL","AMZN")
png("report_figures/01_price_logreturn_reps.png", 1400, 1600, res = 140)
par(mfrow = c(4,2), mar = c(3,3.5,2,0.5), bg = bg)
for (s in reps) {
  p <- clean[clean$ticker == s, ]; r <- ret[ret$ticker == s, ]
  o <- r[is.finite(r$z) & abs(r$z) > 3, ]; m <- label_moves[label_moves$ticker == s, ]
  plot(p$date, p$adjusted_price, type = "l", col = "#2563EB",
       main = paste(s, "adjusted price"), xlab = "", ylab = "USD")
  plot(r$date, r$log_return, type = "h", col = "grey55",
       main = paste(s, "log return"), xlab = "", ylab = "return",
       ylim = extendrange(r$log_return, f = .12))
  abline(h = 0); points(o$date, o$log_return, col = 2, pch = 19)
  text(m$date, m$log_return, format(m$date), pos = 1, cex = .65, col = 2)
}; dev.off()

png("report_figures/02_qq_reps.png", 1200, 1000, res = 140)
par(mfrow = c(2,2), bg = bg)
for (s in reps) {
  x <- na.omit(ret$log_return[ret$ticker == s])
  qqnorm(x, main = paste(s, "normal Q-Q"), pch = 19, cex = .4, col = "#2563EB")
  qqline(x, col = 2)
}; dev.off()

# Generate all 12 stock-specific dynamics and Q-Q plots as supplementary files.
for (s in tickers) {
  p <- clean[clean$ticker == s, ]; r <- ret[ret$ticker == s, ]
  m <- label_moves[label_moves$ticker == s, ]
  png(sprintf("report_figures/07_price_logreturn_%s.png",s),1000,750,res=120)
  par(mfrow=c(2,1)); plot(p$date,p$adjusted_price,type="l",main=paste(s,"price"))
  plot(r$date,r$log_return,type="h",main=paste(s,"log return"),
       ylim=extendrange(r$log_return,f=.12)); text(m$date,m$log_return,format(m$date),pos=1,col=2)
  dev.off()
  png(sprintf("report_figures/08_qq_%s.png",s),700,650,res=120)
  x <- na.omit(r$log_return); qqnorm(x,main=paste(s,"normal Q-Q"),pch=19,cex=.4)
  qqline(x,col=2); dev.off()
}

pw <- reshape(clean[c("date","ticker","adjusted_price")], idvar = "date",
              timevar = "ticker", direction = "wide")
pw <- pw[order(pw$date), ]; pc <- grep("^adjusted", names(pw), value = TRUE)
R <- sapply(pw[pc], function(x) diff(log(x))); R <- R[complete.cases(R), ]
colnames(R) <- sub("^adjusted_price\\.", "", pc)
pairs <- list(c("JPM","BAC"),c("COP","XOM"),c("AAPL","MSFT"),
              c("COP","AAPL"),c("JPM","AMZN"),c("XOM","MCD"))
png("report_figures/03_sector_scatters.png", 1400, 900, res = 140)
par(mfrow = c(2,3), bg = bg)
for (p in pairs) plot(R[,p[1]], R[,p[2]], pch = 19, cex = .25,
  col = "#2563EB", xlab = p[1], ylab = p[2],
  main = sprintf("%s-%s (r=%.2f)", p[1], p[2], cor(R[,p[1]], R[,p[2]])))
dev.off()

# 3. Fixed-share portfolio, VaR/ES, and 2020 Kupiec backtests.
start <- min(clean$date); sh <- clean |> filter(date == start) |>
  transmute(ticker, shares = 1000 / adjusted_price)
pv <- clean |> inner_join(sh, by = "ticker") |> group_by(date) |>
  summarise(value = sum(shares * adjusted_price), .groups = "drop") |>
  arrange(date) |> mutate(loss = -(value / lag(value) - 1))
ins <- pv |> filter(date > start, date <= as.Date("2019-12-31")) |> pull(loss)
oos <- pv |> filter(date >= as.Date("2020-01-01"), date <= as.Date("2020-12-31"))
a <- c(.95,.99)
hist <- data.frame(method="Historical", alpha=a,
  VaR=quantile(ins,a), ES=sapply(a,\(q) mean(ins[ins >= quantile(ins,q)])))
mu <- mean(ins); sig <- sqrt(mean((ins - mu)^2))
norm <- data.frame(method="Normal", alpha=a, VaR=mu+sig*qnorm(a),
  ES=mu+sig*dnorm(qnorm(a))/(1-a))
tf <- fitdistr(ins, "t"); tm <- tf$estimate["m"]; ts <- tf$estimate["s"]
nu <- tf$estimate["df"]; tq <- qt(a,nu)
stud <- data.frame(method="Student-t", alpha=a, VaR=tm+ts*tq,
  ES=tm+ts*(nu+tq^2)/((nu-1)*(1-a))*dt(tq,nu))
risk <- bind_rows(hist,norm,stud); write.csv(risk,"covid_portfolio_var_es_insample.csv",row.names=FALSE)
kupiec <- function(x,n,p) {
  ph <- x/n
  lr <- -2*((n-x)*log(1-p)+x*log(p)-(n-x)*log(1-ph)-x*log(ph))
  c(LR=lr,p_value=pchisq(lr,1,lower.tail=FALSE))
}
backtest <- bind_rows(lapply(seq_len(nrow(risk)), \(i) {
  x <- sum(oos$loss > risk$VaR[i]); k <- kupiec(x,nrow(oos),1-risk$alpha[i])
  data.frame(risk[i,c("method","alpha","VaR")], exceedances=x,
             expected=nrow(oos)*(1-risk$alpha[i]), LR=k[1], p_value=k[2])
}))
write.csv(backtest,"covid_portfolio_var_backtest_2020.csv",row.names=FALSE)
png("report_figures/05_portfolio_oos_var99.png",1200,700,res=140)
plot(oos$date,oos$loss,type="h",col="grey50",xlab="Date",ylab="Loss",
     main="2020 losses and in-sample 99% VaR")
v <- risk$VaR[risk$alpha==.99]; abline(h=v,col=c(4,2,3),lwd=2,lty=1:3)
legend("topright",c("Historical","Normal","Student-t"),col=c(4,2,3),lty=1:3,bty="n")
dev.off()

# 4. Four copula families for all 66 pairs.
U <- pobs(R); ij <- combn(ncol(U),2); fits <- vector("list",ncol(ij))
cmp <- vector("list",ncol(ij))
for (k in seq_len(ncol(ij))) {
  u <- U[,ij[,k]]
  f <- list(
    Gaussian=fitCopula(normalCopula(dim=2,dispstr="un"),u,method="ml"),
    Student_t=fitCopula(tCopula(dim=2,dispstr="un",df.fixed=FALSE),u,method="ml"),
    Gumbel=fitCopula(gumbelCopula(dim=2),u,method="ml"),
    Clayton=fitCopula(claytonCopula(dim=2),u,method="ml"))
  z <- bind_rows(lapply(names(f), \(nm) {
    ll <- as.numeric(logLik(f[[nm]])); kp <- length(coef(f[[nm]]))
    data.frame(family=nm,log_likelihood=ll,AIC=-2*ll+2*kp,BIC=-2*ll+log(nrow(u))*kp)
  })) |> arrange(AIC)
  z$ticker1 <- colnames(U)[ij[1,k]]; z$ticker2 <- colnames(U)[ij[2,k]]
  z$pair <- paste(z$ticker1,z$ticker2,sep="-"); z$best <- seq_len(nrow(z))==1
  fits[[k]] <- f; cmp[[k]] <- z
}
comparison <- bind_rows(cmp)
tailcoef <- function(nm,f) {
  th <- coef(f)
  if(nm=="Gaussian") return(c(0,0))
  if(nm=="Clayton") return(c(2^(-1/th[1]),0))
  if(nm=="Gumbel") return(c(0,2-2^(1/th[1])))
  la <- 2*pt(-sqrt((th[2]+1)*(1-th[1])/(1+th[1])),th[2]+1); c(la,la)
}
tails <- bind_rows(lapply(seq_along(fits), \(k)
  bind_rows(lapply(names(fits[[k]]), \(nm) {
    x <- tailcoef(nm,fits[[k]][[nm]])
    data.frame(pair=cmp[[k]]$pair[1],family=nm,lambda_L=x[1],lambda_U=x[2])
  }))))
write.csv(comparison,"covid_copula_pair_comparison.csv",row.names=FALSE)
write.csv(tails,"covid_copula_tail_dependence.csv",row.names=FALSE)
png("report_figures/04_copula_COP_XOM.png",800,750,res=140)
plot(U[,"COP"],U[,"XOM"],pch=19,cex=.35,col="#2563EB",
     xlab="COP pseudo-observation",ylab="XOM pseudo-observation")
abline(0,1,lty=2); dev.off()

print(normality); print(risk); print(backtest)
print(comparison |> group_by(family) |> summarise(times_best=sum(best),mean_AIC=mean(AIC)))
print(tails |> group_by(family) |> summarise(across(c(lambda_L,lambda_U),mean)))
