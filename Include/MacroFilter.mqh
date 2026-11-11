//+------------------------------------------------------------------+
//|                                                  MacroFilter.mqh |
//|   Economic-event blackout window for EU session trading          |
//+------------------------------------------------------------------+
#ifndef __MACRO_FILTER_MQH__
#define __MACRO_FILTER_MQH__

struct MacroEvent
  {
   datetime          time;
   string            name;
   int               impact;    // 1=low, 2=medium, 3=high
  };

class CMacroFilter
  {
private:
   MacroEvent        m_events[];
   int               m_pre_minutes;
   int               m_post_minutes;
   int               m_min_impact;

   bool              LoadCsv(const string path);

public:
                     CMacroFilter(void);
                    ~CMacroFilter(void) {}

   bool              Init(const string csv_path,
                          const int pre_minutes=60,
                          const int post_minutes=30,
                          const int min_impact=3);

   bool              InBlackout(const datetime now);
   int               NextEventMinutes(const datetime now);
  };

CMacroFilter::CMacroFilter(void):
   m_pre_minutes(60),
   m_post_minutes(30),
   m_min_impact(3)
  {}

bool CMacroFilter::Init(const string csv_path,
                        const int pre_minutes,
                        const int post_minutes,
                        const int min_impact)
  {
   m_pre_minutes  = pre_minutes;
   m_post_minutes = post_minutes;
   m_min_impact   = min_impact;
   ArrayResize(m_events, 0);
   if(csv_path == "") return true;
   return LoadCsv(csv_path);
  }

bool CMacroFilter::LoadCsv(const string path)
  {
   int h = FileOpen(path, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ';');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("MacroFilter: failed to open %s (err=%d)", path, GetLastError());
      return false;
     }

   int count = 0;
   while(!FileIsEnding(h))
     {
      string ts     = FileReadString(h);
      string name   = FileReadString(h);
      string impact = FileReadString(h);
      if(ts == "") continue;
      datetime t = StringToTime(ts);
      if(t <= 0) continue;

      ArrayResize(m_events, count+1);
      m_events[count].time   = t;
      m_events[count].name   = name;
      m_events[count].impact = (int)StringToInteger(impact);
      count++;
     }
   FileClose(h);
   PrintFormat("MacroFilter: loaded %d events from %s", count, path);
   return true;
  }

bool CMacroFilter::InBlackout(const datetime now)
  {
   int n = ArraySize(m_events);
   for(int i=0; i<n; i++)
     {
      if(m_events[i].impact < m_min_impact) continue;
      datetime start = m_events[i].time - m_pre_minutes*60;
      datetime end   = m_events[i].time + m_post_minutes*60;
      if(now >= start && now <= end) return true;
     }
   return false;
  }

int CMacroFilter::NextEventMinutes(const datetime now)
  {
   int n = ArraySize(m_events);
   int best = INT_MAX;
   for(int i=0; i<n; i++)
     {
      if(m_events[i].impact < m_min_impact) continue;
      if(m_events[i].time < now) continue;
      int diff = (int)((m_events[i].time - now)/60);
      if(diff < best) best = diff;
     }
   return (best == INT_MAX) ? -1 : best;
  }

#endif
