    
    
    
    # 迭代器适配器：包装任意 IIterable 提供一个带 index / value 的游标式迭代器（foreach 底层常用），支持复位、前进与取值。
    public class Iterater interface IIterator
    {        
        _start = 0
        public _index = 0
        _value = null
        IIterator _iterator = null
        _isDone = false;


        _init_( IIterable __it )
        {
            this._iterator = __it.iterator();
            this._iterator.reset()
        }
        get int index(){ ret this._index }
        get object value()
        {
             ret this._value 
        }

        override void reset()
        {
            this._isDone = false
            this._start = 0
            this._index = 0
            this._value = null
        }
        override bool moveNext()
        {
            if this._isDone
            {
                ret false
            }
            this._index++
            var flag = this._iterator.moveNext()
            this._value = this._iterator.current()
            this._isDone = !flag
            ret flag
        }
        override get object current()
        {
            this._value = this._iterator.current()
            ret this._value
        }
        override void release()
        {
            
        }
        override string toString()
        {
            if( this._value != null )
            {
                ret this._value.toString()
            }
            else
            {
                ret ""
            }
        }
    }
    
    # 泛型迭代器适配器：强类型版 Iterater，包装 IIterable<T> 提供带 index / value 的游标式迭代。
    public class Iterater<T> interface IIterator<T>
    {
        _start = 0
        public _index = 0
        T _value = null
        IIterator<T> _iterator = null
        _isDone = false;

        _init_( IIterable<T> __it )
        {
            this._iterator = __it.iterator();
            this._iterator.reset()
        }
        get int index(){ ret this._index }
        get T value()
        {
             ret this._value 
        }

        override void reset()
        {
            this._isDone = false
            this._start = 0
            this._index = 0
            this._value = null
        }
        override bool moveNext()
        {
            if this._isDone
            {
                ret false
            }
            this._index++
            var flag = this._iterator.moveNext()
            this._value = this._iterator.current()
            this._isDone = !flag
            ret flag
        }
        override get T current()
        {
            #this._value = this._iterator.current()
            ret this._value
        }
        override void release()
        {
            
        }
        override string toString()
        {
            if( this._value != null )
            {
                ret this._value.toString()
            }
            else
            {
                ret ""
            }
        }
    }