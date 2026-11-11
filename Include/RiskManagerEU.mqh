//+------------------------------------------------------------------+
//|                                                RiskManagerEU.mqh |
//|   ATR-based dynamic position sizing with streak decay            |
//+------------------------------------------------------------------+
#ifndef __RISK_MANAGER_EU_MQH__
#define __RISK_MANAGER_EU_MQH__

class CRiskManagerEU
  {
private:
   string            m_symbol;
   double            m_base_risk_pct;
   double            m_atr_mult_sl;
   int               m_max_positions;
   int               m_loss_streak;

   double            StreakFactor(void) const;

public:
                     CRiskManagerEU(void);
                    ~CRiskManagerEU(void) {}

   void              Init(const string symbol,
                          const double base_risk_pct=0.005,
                          const double atr_mult_sl=1.5,
                          const int max_positions=2);

   void              OnTradeClosed(const double pnl);

   double            LotFor(const double atr);
   double            StopLossPrice(const int direction, const double entry, const double atr);
   double            TakeProfitPrice(const int direction, const double entry, const double mid);

   int               MaxPositions(void) const { return m_max_positions; }
  };

CRiskManagerEU::CRiskManagerEU(void):
   m_symbol(""),
   m_base_risk_pct(0.005),
   m_atr_mult_sl(1.5),
   m_max_positions(2),
   m_loss_streak(0)
  {}

void CRiskManagerEU::Init(const string symbol,
                          const double base_risk_pct,
                          const double atr_mult_sl,
                          const int max_positions)
  {
   m_symbol        = symbol;
   m_base_risk_pct = base_risk_pct;
   m_atr_mult_sl   = atr_mult_sl;
   m_max_positions = max_positions;
   m_loss_streak   = 0;
  }

void CRiskManagerEU::OnTradeClosed(const double pnl)
  {
   if(pnl < 0.0)      m_loss_streak++;
   else if(pnl > 0.0) m_loss_streak = 0;
  }

double CRiskManagerEU::StreakFactor(void) const
  {
   if(m_loss_streak >= 4) return 0.4;
   if(m_loss_streak >= 2) return 0.6;
   return 1.0;
  }

double CRiskManagerEU::LotFor(const double atr)
  {
   if(atr <= 0.0) return 0.0;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * m_base_risk_pct * StreakFactor();

   double tick_val = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val <= 0.0 || tick_sz <= 0.0) return 0.0;

   double sl_price_delta = atr * m_atr_mult_sl;
   double loss_per_lot   = (sl_price_delta / tick_sz) * tick_val;
   if(loss_per_lot <= 0.0) return 0.0;

   double lot = risk_money / loss_per_lot;

   double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(step > 0.0) lot = MathFloor(lot / step) * step;
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   return lot;
  }

double CRiskManagerEU::StopLossPrice(const int direction, const double entry, const double atr)
  {
   double d = atr * m_atr_mult_sl;
   return (direction > 0) ? entry - d : entry + d;
  }

double CRiskManagerEU::TakeProfitPrice(const int direction, const double entry, const double mid)
  {
   // Mean reversion target is the middle Bollinger band.
   // Guard against degenerate mid (e.g. 0) by falling back to a 1R target.
   if(mid <= 0.0) return (direction > 0) ? entry + (entry*0.001) : entry - (entry*0.001);
   return mid;
  }

#endif
