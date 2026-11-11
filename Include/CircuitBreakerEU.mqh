//+------------------------------------------------------------------+
//|                                             CircuitBreakerEU.mqh |
//|   5 layers reused from USD/JPY version + layer 6 (correlation)   |
//+------------------------------------------------------------------+
#ifndef __CIRCUIT_BREAKER_EU_MQH__
#define __CIRCUIT_BREAKER_EU_MQH__

enum ENUM_CB_STATE
  {
   CB_OK          = 0,
   CB_HALT_DAY    = 1,
   CB_HALT_WEEK   = 2,
   CB_HALT_STREAK = 3,
   CB_HALT_SPREAD = 4,
   CB_HALT_VIX    = 5,
   CB_HALT_CORR   = 6
  };

class CCircuitBreakerEU
  {
private:
   string            m_symbol;
   string            m_dxy_symbol;

   double            m_daily_loss_pct;
   double            m_weekly_loss_pct;
   int               m_streak_limit;
   double            m_spread_mult;
   double            m_vix_threshold;
   double            m_corr_threshold;

   double            m_initial_balance_day;
   double            m_initial_balance_week;
   datetime          m_day_start;
   datetime          m_week_start;
   datetime          m_halt_until;

   int               m_loss_streak;
   double            m_avg_spread;
   int               m_spread_samples;

   int               m_corr_window;

   bool              IsNewDay(const datetime t);
   bool              IsNewWeek(const datetime t);
   double            Correlation(const string s1, const string s2, const int bars);

public:
                     CCircuitBreakerEU(void);
                    ~CCircuitBreakerEU(void) {}

   void              Init(const string symbol,
                          const string dxy_symbol="USDX",
                          const double daily_loss_pct=0.02,
                          const double weekly_loss_pct=0.05,
                          const int streak_limit=5,
                          const double spread_mult=3.0,
                          const double vix_threshold=30.0,
                          const double corr_threshold=0.30,
                          const int corr_window=30);

   void              OnTradeClosed(const double pnl);
   void              OnSpreadSample(const double spread_points);

   ENUM_CB_STATE     Check(const double current_vix);
  };

CCircuitBreakerEU::CCircuitBreakerEU(void):
   m_symbol(""),
   m_dxy_symbol("USDX"),
   m_daily_loss_pct(0.02),
   m_weekly_loss_pct(0.05),
   m_streak_limit(5),
   m_spread_mult(3.0),
   m_vix_threshold(30.0),
   m_corr_threshold(0.30),
   m_initial_balance_day(0.0),
   m_initial_balance_week(0.0),
   m_day_start(0),
   m_week_start(0),
   m_halt_until(0),
   m_loss_streak(0),
   m_avg_spread(0.0),
   m_spread_samples(0),
   m_corr_window(30)
  {}

void CCircuitBreakerEU::Init(const string symbol,
                             const string dxy_symbol,
                             const double daily_loss_pct,
                             const double weekly_loss_pct,
                             const int streak_limit,
                             const double spread_mult,
                             const double vix_threshold,
                             const double corr_threshold,
                             const int corr_window)
  {
   m_symbol          = symbol;
   m_dxy_symbol      = dxy_symbol;
   m_daily_loss_pct  = daily_loss_pct;
   m_weekly_loss_pct = weekly_loss_pct;
   m_streak_limit    = streak_limit;
   m_spread_mult     = spread_mult;
   m_vix_threshold   = vix_threshold;
   m_corr_threshold  = corr_threshold;
   m_corr_window     = corr_window;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   m_initial_balance_day  = bal;
   m_initial_balance_week = bal;
   m_day_start  = TimeCurrent();
   m_week_start = TimeCurrent();
  }

bool CCircuitBreakerEU::IsNewDay(const datetime t)
  {
   MqlDateTime a, b;
   TimeToStruct(m_day_start, a);
   TimeToStruct(t, b);
   return (a.year!=b.year || a.mon!=b.mon || a.day!=b.day);
  }

bool CCircuitBreakerEU::IsNewWeek(const datetime t)
  {
   return (t - m_week_start) >= 7*24*3600;
  }

void CCircuitBreakerEU::OnTradeClosed(const double pnl)
  {
   if(pnl < 0.0)
      m_loss_streak++;
   else if(pnl > 0.0)
      m_loss_streak = 0;
  }

void CCircuitBreakerEU::OnSpreadSample(const double spread_points)
  {
   m_spread_samples++;
   m_avg_spread += (spread_points - m_avg_spread) / (double)m_spread_samples;
  }

double CCircuitBreakerEU::Correlation(const string s1, const string s2, const int bars)
  {
   double a[], b[];
   ArraySetAsSeries(a, true);
   ArraySetAsSeries(b, true);
   int na = CopyClose(s1, PERIOD_H1, 0, bars+1, a);
   int nb = CopyClose(s2, PERIOD_H1, 0, bars+1, b);
   if(na < bars+1 || nb < bars+1) return 0.0;

   double ra[], rb[];
   ArrayResize(ra, bars);
   ArrayResize(rb, bars);
   for(int i=0; i<bars; i++)
     {
      ra[i] = (a[i+1]!=0.0) ? (a[i] - a[i+1]) / a[i+1] : 0.0;
      rb[i] = (b[i+1]!=0.0) ? (b[i] - b[i+1]) / b[i+1] : 0.0;
     }

   double ma=0.0, mb=0.0;
   for(int i=0; i<bars; i++) { ma += ra[i]; mb += rb[i]; }
   ma /= bars; mb /= bars;

   double num=0.0, da=0.0, db=0.0;
   for(int i=0; i<bars; i++)
     {
      double xa = ra[i]-ma;
      double xb = rb[i]-mb;
      num += xa*xb;
      da  += xa*xa;
      db  += xb*xb;
     }
   double denom = MathSqrt(da*db);
   if(denom <= 0.0) return 0.0;
   return num / denom;
  }

ENUM_CB_STATE CCircuitBreakerEU::Check(const double current_vix)
  {
   datetime now = TimeCurrent();

   if(now < m_halt_until) return CB_HALT_STREAK;

   if(IsNewDay(now))
     {
      m_initial_balance_day = AccountInfoDouble(ACCOUNT_BALANCE);
      m_day_start = now;
     }
   if(IsNewWeek(now))
     {
      m_initial_balance_week = AccountInfoDouble(ACCOUNT_BALANCE);
      m_week_start = now;
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double day_dd  = (m_initial_balance_day  - eq) / m_initial_balance_day;
   double week_dd = (m_initial_balance_week - eq) / m_initial_balance_week;

   if(day_dd  >= m_daily_loss_pct)  return CB_HALT_DAY;
   if(week_dd >= m_weekly_loss_pct) return CB_HALT_WEEK;

   if(m_loss_streak >= m_streak_limit)
     {
      m_halt_until = now + 24*3600;
      m_loss_streak = 0;
      return CB_HALT_STREAK;
     }

   long spread_now = 0;
   if(SymbolInfoInteger(m_symbol, SYMBOL_SPREAD, spread_now)
      && m_spread_samples > 10
      && (double)spread_now > m_avg_spread * m_spread_mult)
      return CB_HALT_SPREAD;

   if(current_vix > m_vix_threshold) return CB_HALT_VIX;

   // Layer 6: EUR/USD vs DXY should be strongly negative.
   // If rolling correlation rises above -threshold (i.e. corr > -0.30),
   // the usual regime is broken — stop opening new trades.
   if(m_dxy_symbol != "")
     {
      double c = Correlation(m_symbol, m_dxy_symbol, m_corr_window);
      if(c > -m_corr_threshold) return CB_HALT_CORR;
     }

   return CB_OK;
  }

#endif
