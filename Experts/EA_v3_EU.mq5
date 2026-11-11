//+------------------------------------------------------------------+
//|                                                     EA_v3_EU.mq5 |
//|   EUR/USD mean-reversion Expert Advisor (v3 EU branch)           |
//+------------------------------------------------------------------+
#property copyright "EA_v3 EU branch"
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>
#include "../Include/SignalEU.mqh"
#include "../Include/CircuitBreakerEU.mqh"
#include "../Include/MacroFilter.mqh"
#include "../Include/RiskManagerEU.mqh"

input group "=== Symbols ==="
input string InpDxySymbol      = "USDX";
input string InpVixSymbol      = "VIX";

input group "=== Signal ==="
input int    InpBBPeriod       = 20;
input double InpBBDev          = 2.0;
input int    InpRsiPeriod      = 14;
input int    InpZPeriod        = 20;

input group "=== Risk ==="
input double InpRiskPct        = 0.005;
input double InpAtrMultSL      = 1.5;
input int    InpMaxPositions   = 2;
input int    InpTimeStopBars   = 48;

input group "=== Circuit breaker ==="
input double InpDailyLossPct   = 0.02;
input double InpWeeklyLossPct  = 0.05;
input int    InpStreakLimit    = 5;
input double InpSpreadMult     = 3.0;
input double InpVixThreshold   = 30.0;
input double InpCorrThreshold  = 0.30;
input int    InpCorrWindow     = 30;

input group "=== Macro filter ==="
input string InpCalendarCsv    = "macro_events_eu.csv";
input int    InpPreMinutes     = 60;
input int    InpPostMinutes    = 30;
input int    InpMinImpact      = 3;

input group "=== Misc ==="
input ulong  InpMagic          = 30300;

CTrade            trade;
CSignalEU         signal;
CCircuitBreakerEU breaker;
CMacroFilter      macro;
CRiskManagerEU    risk;

datetime          g_last_bar = 0;

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!signal.Init(_Symbol, PERIOD_H1, InpBBPeriod, InpBBDev, InpRsiPeriod, InpZPeriod))
     {
      Print("EA_v3_EU: signal init failed");
      return INIT_FAILED;
     }

   breaker.Init(_Symbol, InpDxySymbol,
                InpDailyLossPct, InpWeeklyLossPct,
                InpStreakLimit, InpSpreadMult,
                InpVixThreshold, InpCorrThreshold, InpCorrWindow);

   macro.Init(InpCalendarCsv, InpPreMinutes, InpPostMinutes, InpMinImpact);
   risk .Init(_Symbol, InpRiskPct, InpAtrMultSL, InpMaxPositions);

   Print("EA_v3_EU: initialized on ", _Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   signal.Release();
  }

int CountOwnPositions(void)
  {
   int total = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      total++;
     }
   return total;
  }

void ManageOpen(void)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;

      long  type   = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot  = (datetime)PositionGetInteger(POSITION_TIME);

      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      // Mean-reversion mid-line exit
      if(signal.CheckExit(dir, entry))
        {
         trade.PositionClose(tk);
         continue;
        }

      // Time stop
      int bars_held = iBarShift(_Symbol, PERIOD_H1, ot, false);
      if(bars_held >= InpTimeStopBars)
         trade.PositionClose(tk);
     }
  }

double LatestVix(void)
  {
   double v[1];
   ArraySetAsSeries(v, true);
   if(InpVixSymbol == "") return 0.0;
   if(CopyClose(InpVixSymbol, PERIOD_H1, 0, 1, v) < 1) return 0.0;
   return v[0];
  }

void OnTick()
  {
   long spread_pts = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread_pts))
      breaker.OnSpreadSample((double)spread_pts);

   ManageOpen();

   datetime bar_time = iTime(_Symbol, PERIOD_H1, 0);
   if(bar_time == g_last_bar) return;
   g_last_bar = bar_time;

   // Macro blackout
   if(macro.InBlackout(TimeCurrent())) return;

   // Circuit breaker
   ENUM_CB_STATE cb = breaker.Check(LatestVix());
   if(cb != CB_OK)
     {
      static ENUM_CB_STATE last_cb = CB_OK;
      if(cb != last_cb)
        {
         PrintFormat("EA_v3_EU: circuit breaker state=%d — new entries halted", cb);
         last_cb = cb;
        }
      return;
     }

   if(CountOwnPositions() >= risk.MaxPositions()) return;

   ENUM_SIGNAL_EU s = signal.CheckEntry();
   if(s == SIGNAL_EU_NONE) return;

   double atr = signal.ATR(14);
   double lot = risk.LotFor(atr);
   if(lot <= 0.0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = signal.MidLine();

   if(s == SIGNAL_EU_LONG)
     {
      double sl = risk.StopLossPrice(1, ask, atr);
      double tp = risk.TakeProfitPrice(1, ask, mid);
      trade.Buy(lot, _Symbol, ask, sl, tp, "EU_MR_long");
     }
   else if(s == SIGNAL_EU_SHORT)
     {
      double sl = risk.StopLossPrice(-1, bid, atr);
      double tp = risk.TakeProfitPrice(-1, bid, mid);
      trade.Sell(lot, _Symbol, bid, sl, tp, "EU_MR_short");
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))           return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   breaker.OnTradeClosed(pnl);
   risk   .OnTradeClosed(pnl);
  }
