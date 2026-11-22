


namespace SimpleLanguage.Core
{
    public enum ELeftRightOpSign
    {
        Add,
        Minus,
        Multiply,
        Divide,
        Modulo,
        InclusiveOr,
        Combine,
        XOR,
        Shi,
        Shr,
        Equal,
        NotEqual,
        Greater,
        GreaterOrEqual,
        Less,
        LessOrEqual,
        And,
        Or,
        Cast,
        IsType,
    }
    public enum ESingleOpSign
    {
        None,
        Neg,
        Not,
        Xor,
    }
    public class MetaExpressNode
    {
        public int opLevel
        {
            get
            {
                return MetaTypeFactory.GetOpLevelByMetaType(m_MetaDefineType);
            }
        }

        public MetaType metaDefineType => m_MetaDefineType;
        public MetaClass ownerMetaClass => m_OwnerMetaClass;

        protected MetaClass m_OwnerMetaClass = null;
        protected MetaBlockStatements m_OwnerMetaBlockStatements = null;
        protected MetaType m_MetaDefineType = null;
        public int CalcParseLevel(int level) { return level; }
        public void CalcReturnType() { }
        public void Parse(AllowUseSettings auc) { }
        public MetaClass GetReturnMetaClass()
        {
            if (m_MetaDefineType == null)
            {
                GetReturnMetaDefineType();
            }
            return m_MetaDefineType?.metaClass;
        }
        public void SetMetaType( MetaType mt )
        {
            m_MetaDefineType = mt;
        }
        public MetaType GetReturnMetaDefineType()
        {
            return m_MetaDefineType;
        }
        public string ToFormatString()
        {
            return "";
        }
        public string ToTokenString()
        {
            return "";
        }

    }
}
