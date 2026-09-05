//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.400"
#property description "EAGOLD - Independent BUY and SELL operation engine."

input int    MagicNumber  = 1001;
input double Lots         = 0.01;
input int    FirstStep    = 150;
input int    ProfitTarget = 150;
input int    Slippage     = 10;

//====================================================================
// CONTADORES
//====================================================================

int CountOpenOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return(count);
}

int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      int type = OrderType();
      if(type == OP_BUYLIMIT || type == OP_BUYSTOP ||
         type == OP_SELLLIMIT || type == OP_SELLSTOP)
         count++;
   }
   return(count);
}

//====================================================================
// CÁLCULOS
//====================================================================

double StepPrice()
{
   return(FirstStep * Point);
}

double OrderProfitPoints()
{
   if(OrderType() == OP_BUY)
      return((Bid - OrderOpenPrice()) / Point);

   if(OrderType() == OP_SELL)
      return((OrderOpenPrice() - Ask) / Point);

   return(0);
}

//====================================================================
// ABRE UMA OPERAÇÃO INDEPENDENTE
//====================================================================
//
// BUY:
//   abre BUY a mercado
//   cria SELL pendente FirstStep abaixo da entrada
//
// SELL:
//   abre SELL a mercado
//   cria BUY pendente FirstStep acima da entrada
//
// IMPORTANTE:
// cada operação é independente. Uma nova operação não cancela,
// substitui ou depende das ordens pendentes de operações anteriores.
//====================================================================

bool StartIndependentOperation(int direction)
{
   RefreshRates();

   int marketType;
   int pendingType;
   double marketPrice;
   double pendingPrice;

   if(direction == OP_BUY)
   {
      marketType   = OP_BUY;
      pendingType  = OP_SELLSTOP;
      marketPrice  = NormalizeDouble(Ask, Digits);
      pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
   }
   else if(direction == OP_SELL)
   {
      marketType   = OP_SELL;
      pendingType  = OP_BUYSTOP;
      marketPrice  = NormalizeDouble(Bid, Digits);
      pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }
   else
   {
      return(false);
   }

   int marketTicket = OrderSend(
      Symbol(), marketType, Lots, marketPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD BUY" : "EAGOLD SELL",
      MagicNumber, 0, clrNONE
   );

   if(marketTicket < 0)
   {
      Print("EAGOLD ERROR - Market order failed. Direction=",
            direction == OP_BUY ? "BUY" : "SELL",
            " Error=", GetLastError());
      return(false);
   }

   // Usa o preço de execução real da ordem como referência do FirstStep.
   if(OrderSelect(marketTicket, SELECT_BY_TICKET))
   {
      marketPrice = OrderOpenPrice();

      if(direction == OP_BUY)
         pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
      else
         pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }

   RefreshRates();

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   // A ordem de proteção/continuidade é sempre criada como STOP na
   // direção oposta da operação que acabou de nascer.
   if(direction == OP_BUY)
   {
      if((Bid - pendingPrice) < minimumDistance)
      {
         Print("EAGOLD ERROR - SELL STOP too close to market. Ticket=",
               marketTicket, " Error condition: StopLevel.");
         return(true);
      }
   }
   else
   {
      if((pendingPrice - Ask) < minimumDistance)
      {
         Print("EAGOLD ERROR - BUY STOP too close to market. Ticket=",
               marketTicket, " Error condition: StopLevel.");
         return(true);
      }
   }

   ResetLastError();

   int pendingTicket = OrderSend(
      Symbol(), pendingType, Lots, pendingPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD SELL" : "EAGOLD BUY",
      MagicNumber, 0, clrNONE
   );

   if(pendingTicket < 0)
   {
      Print("EAGOLD ERROR - Opposite pending order failed. MarketTicket=",
            marketTicket,
            " Type=", pendingType,
            " Price=", DoubleToString(pendingPrice, Digits),
            " Error=", GetLastError());
      return(true);
   }

   Print("EAGOLD - Independent operation started. Direction=",
         direction == OP_BUY ? "BUY" : "SELL",
         " MarketTicket=", marketTicket,
         " MarketPrice=", DoubleToString(marketPrice, Digits),
         " PendingTicket=", pendingTicket,
         " PendingPrice=", DoubleToString(pendingPrice, Digits),
         " FirstStep=", FirstStep, " points");

   return(true);
}

//====================================================================
// GERENCIAMENTO DAS ORDENS
//====================================================================

void ManageOrders()
{
   RefreshRates();

   // Processa uma ordem por vez. Após um fechamento com gain, uma nova
   // operação NA MESMA DIREÇÃO é aberta imediatamente, sem olhar se
   // existem outras operações ou pendentes de outros ciclos.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int direction = OrderType();
      double profitPoints = OrderProfitPoints();

      if(profitPoints < ProfitTarget)
         continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double closePrice = direction == OP_BUY ? Bid : Ask;

      ResetLastError();

      bool closed = OrderClose(
         ticket, lots, closePrice, Slippage, clrNONE
      );

      if(!closed)
      {
         Print("EAGOLD ERROR - OrderClose failed. Ticket=",
               ticket, " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - Order closed by ProfitTarget. Ticket=", ticket,
            " Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " ProfitPoints=", DoubleToString(profitPoints, 1));

      //==============================================================
      // NOVA OPERAÇÃO INDEPENDENTE
      //==============================================================
      //
      // BUY bateu gain -> abre NOVA BUY.
      // A SELL pendente original continua intacta.
      //
      // SELL bateu gain -> abre NOVA SELL.
      // As BUYs/pending BUYs existentes continuam intactas.
      //==============================================================

      StartIndependentOperation(direction);
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==================================================");
   Print("EAGOLD v0.4.0 INITIALIZED");
   Print("Independent BUY/SELL operation engine");
   Print("FirstStep    = ", FirstStep, " points");
   Print("ProfitTarget = ", ProfitTarget, " points");
   Print("MagicNumber  = ", MagicNumber);
   Print("Lots         = ", DoubleToString(Lots, 2));
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("EAGOLD v0.4.0 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   ManageOrders();

   // Se o EA foi iniciado sem nenhuma ordem própria, começa a primeira
   // operação BUY. Depois disso, todas as operações passam a ser
   // independentes e são geradas pelos próprios fechamentos com gain.
   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY);
}

//+------------------------------------------------------------------+
