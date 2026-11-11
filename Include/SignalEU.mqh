//+------------------------------------------------------------------+
//|                                                     SignalEU.mqh |
//|                      EUR/USD mean-reversion signal generator     |
//+------------------------------------------------------------------+
#ifndef __SIGNAL_EU_MQH__
#define __SIGNAL_EU_MQH__

enum ENUM_SIGNAL_EU
  {
   SIGNAL_EU_NONE  = 0,
   SIGNAL_EU_LONG  = 1,
   SIGNAL_EU_SHORT = -1
  };

class CSignalEU
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;

   int               m_h_bb;
   int               m_h_rsi;
   int               m_h_ma;
   int               m_h_atr;

   int               m_bb_period;
   double            m_bb_dev;
   int               m_rsi_period;
   int               m_z_period;
   double            m_z_threshold;
   double            m_rsi_long;
   double            m_rsi_short;

public:
                     CSignalEU(void);
                    ~CSignalEU(void);

   bool              Init(const string symbol,
                          const ENUM_TIMEFRAMES tf,
                          const int bb_period=20,
                          const double bb_dev=2.0,
                          const int rsi_period=14,
                          const int z_period=20);
   void              Release(void);

   ENUM_SIGNAL_EU    CheckEntry(void);
   bool              CheckExit(const int direction, const double entry_price);

   double            MidLine(void);
   double            ATR(const int period=14);
  };

CSignalEU::CSignalEU(void):
   m_symbol(""),
   m_tf(PERIOD_H1),
   m_h_bb(INVALID_HANDLE),
   m_h_rsi(INVALID_HANDLE),
   m_h_ma(INVALID_HANDLE),
   m_h_atr(INVALID_HANDLE),
   m_bb_period(20),
   m_bb_dev(2.0),
   m_rsi_period(14),
   m_z_period(20),
   m_z_threshold(2.0),
   m_rsi_long(30.0),
   m_rsi_short(70.0)
  {}

CSignalEU::~CSignalEU(void)
  {
   Release();
  }

bool CSignalEU::Init(const string symbol,
                     const ENUM_TIMEFRAMES tf,
                     const int bb_period,
                     const double bb_dev,
                     const int rsi_period,
                     const int z_period)
  {
   m_symbol     = symbol;
   m_tf         = tf;
   m_bb_period  = bb_period;
   m_bb_dev     = bb_dev;
   m_rsi_period = rsi_period;
   m_z_period   = z_period;

   m_h_bb  = iBands(m_symbol, m_tf, m_bb_period, 0, m_bb_dev, PRICE_CLOSE);
   m_h_rsi = iRSI(m_symbol, m_tf, m_rsi_period, PRICE_CLOSE);
   m_h_ma  = iMA(m_symbol, m_tf, m_bb_period, 0, MODE_SMA, PRICE_CLOSE);
   m_h_atr = iATR(m_symbol, m_tf, 14);

   if(m_h_bb==INVALID_HANDLE || m_h_rsi==INVALID_HANDLE
      || m_h_ma==INVALID_HANDLE || m_h_atr==INVALID_HANDLE)
     {
      PrintFormat("SignalEU: indicator handle failed (bb=%d rsi=%d ma=%d atr=%d)",
                  m_h_bb, m_h_rsi, m_h_ma, m_h_atr);
      return false;
     }
   return true;
  }

void CSignalEU::Release(void)
  {
   if(m_h_bb !=INVALID_HANDLE) { IndicatorRelease(m_h_bb);  m_h_bb =INVALID_HANDLE; }
   if(m_h_rsi!=INVALID_HANDLE) { IndicatorRelease(m_h_rsi); m_h_rsi=INVALID_HANDLE; }
   if(m_h_ma !=INVALID_HANDLE) { IndicatorRelease(m_h_ma);  m_h_ma =INVALID_HANDLE; }
   if(m_h_atr!=INVALID_HANDLE) { IndicatorRelease(m_h_atr); m_h_atr=INVALID_HANDLE; }
  }

ENUM_SIGNAL_EU CSignalEU::CheckEntry(void)
  {
   double upper[2], lower[2], mid[2], rsi[2];
   double closes[];
   ArraySetAsSeries(upper,  true);
   ArraySetAsSeries(lower,  true);
   ArraySetAsSeries(mid,    true);
   ArraySetAsSeries(rsi,    true);
   ArraySetAsSeries(closes, true);

   if(CopyBuffer(m_h_bb, 1, 0, 2, upper)  < 2) return SIGNAL_EU_NONE;
   if(CopyBuffer(m_h_bb, 2, 0, 2, lower)  < 2) return SIGNAL_EU_NONE;
   if(CopyBuffer(m_h_bb, 0, 0, 2, mid)    < 2) return SIGNAL_EU_NONE;
   if(CopyBuffer(m_h_rsi, 0, 0, 2, rsi)   < 2) return SIGNAL_EU_NONE;

   if(CopyClose(m_symbol, m_tf, 0, m_z_period+5, closes) < m_z_period) return SIGNAL_EU_NONE;

   double sum=0.0, sum2=0.0;
   for(int i=1; i<=m_z_period; i++)
     {
      sum  += closes[i];
      sum2 += closes[i]*closes[i];
     }
   double mean = sum / m_z_period;
   double var  = sum2 / m_z_period - mean*mean;
   if(var <= 0.0) return SIGNAL_EU_NONE;
   double sd = MathSqrt(var);
   double z  = (closes[1] - mean) / sd;

   int down_count=0, up_count=0;
   for(int i=1; i<=5 && i<ArraySize(closes)-1; i++)
     {
      if(closes[i] < closes[i+1]) down_count++;
      else if(closes[i] > closes[i+1]) up_count++;
     }

   double close_1 = closes[1];

   if(close_1 < lower[1] && rsi[1] < m_rsi_long && z < -m_z_threshold && down_count >= 3)
      return SIGNAL_EU_LONG;

   if(close_1 > upper[1] && rsi[1] > m_rsi_short && z > m_z_threshold && up_count >= 3)
      return SIGNAL_EU_SHORT;

   return SIGNAL_EU_NONE;
  }

bool CSignalEU::CheckExit(const int direction, const double entry_price)
  {
   double mid[1];
   ArraySetAsSeries(mid, true);
   if(CopyBuffer(m_h_ma, 0, 0, 1, mid) < 1) return false;

   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

   if(direction > 0 && bid >= mid[0]) return true;
   if(direction < 0 && ask <= mid[0]) return true;
   return false;
  }

double CSignalEU::MidLine(void)
  {
   double mid[1];
   ArraySetAsSeries(mid, true);
   if(CopyBuffer(m_h_ma, 0, 0, 1, mid) < 1) return 0.0;
   return mid[0];
  }

double CSignalEU::ATR(const int period)
  {
   double atr[1];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(m_h_atr, 0, 0, 1, atr) < 1) return 0.0;
   return atr[0];
  }

#endif
